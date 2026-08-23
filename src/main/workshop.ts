import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type {
  CustomPetStageDefinition,
  CustomPetTemplate,
  GenerationJob,
  GenerationJobView,
  StoredGenerationRequest,
  WorkshopProgress
} from "../shared/types.js";
import type { SidekinPaths } from "./paths.js";
import { readJSON, safeIdentifier, writeJSON, atomicWrite } from "./file-store.js";
import { OpenAIImageClient, type ImageClient } from "./openai-client.js";
import { normalizeReference, prepareGeneratedAsset } from "./image-processor.js";
import { TemplateStore } from "./template-store.js";
import { mediaURL } from "../shared/media.js";

const CANONICAL_THRESHOLDS = [0, 20, 75, 180, 360];
const MAX_REFERENCE_BYTES = 24 * 1024 * 1024;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundedText(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > maximum || value.includes("\0")) throw new Error(`${label} is invalid.`);
  return value.trim();
}

function validDate(value: unknown, label: string): string {
  if (typeof value !== "string" || !Number.isFinite(new Date(value).getTime())) throw new Error(`${label} is invalid.`);
  return new Date(value).toISOString();
}

function thresholds(count: number): number[] {
  if (count === 1) return [0];
  if (count === 5) return CANONICAL_THRESHOLDS;
  return Array.from({ length: count }, (_, index) => {
    const position = index / (count - 1) * (CANONICAL_THRESHOLDS.length - 1);
    const lower = Math.floor(position);
    const upper = Math.min(CANONICAL_THRESHOLDS.length - 1, lower + 1);
    const fraction = position - lower;
    return Math.round(CANONICAL_THRESHOLDS[lower]! + (CANONICAL_THRESHOLDS[upper]! - CANONICAL_THRESHOLDS[lower]!) * fraction);
  });
}

export class WorkshopService {
  private activeJobID?: string;
  private cancelled = false;

  constructor(
    private readonly paths: SidekinPaths,
    private readonly templates: TemplateStore,
    private readonly client: ImageClient = new OpenAIImageClient()
  ) {}

  private directory(id: string): string { return path.join(this.paths.jobs, safeIdentifier(id)); }
  private manifest(id: string): string { return path.join(this.directory(id), "job.json"); }
  private raw(id: string, index: number): string { return path.join(this.directory(id), `raw-stage-${String(index + 1).padStart(2, "0")}.png`); }
  private processed(id: string, index: number): string { return path.join(this.directory(id), `processed-stage-${String(index + 1).padStart(2, "0")}.png`); }

  private async loadJob(id: string): Promise<GenerationJob | undefined> {
    safeIdentifier(id);
    const raw = await readJSON<unknown>(this.manifest(id));
    if (!raw) return undefined;
    if (!isRecord(raw) || raw.schemaVersion !== 1 || raw.id !== id) throw new Error("Generation job manifest is invalid.");
    const requestRaw = raw.request;
    if (!isRecord(requestRaw) || !Array.isArray(requestRaw.stageNames)) throw new Error("Generation job request is invalid.");
    const request: StoredGenerationRequest = {
      templateName: boundedText(requestRaw.templateName, "Template name", 60),
      description: boundedText(requestRaw.description, "Description", 2_000),
      artDirection: boundedText(requestRaw.artDirection, "Art direction", 1_000),
      mode: requestRaw.mode as StoredGenerationRequest["mode"],
      quality: requestRaw.quality as StoredGenerationRequest["quality"],
      stageNames: requestRaw.stageNames.map((name, index) => boundedText(name, `Stage ${index + 1}`, 64)),
      fallbackTheme: boundedText(requestRaw.fallbackTheme, "Fallback theme", 96),
      motionProfile: typeof requestRaw.motionProfile === "string" ? requestRaw.motionProfile : undefined,
      referencePath: existsSync(path.join(this.directory(id), "reference.png")) ? "reference.png" : undefined
    };
    this.validateRequest(request);
    const templateID = boundedText(raw.templateID, "Template ID", 96);
    safeIdentifier(templateID);
    if (!(["ready", "running", "failed", "cancelled"] as unknown[]).includes(raw.state)) throw new Error("Generation job state is invalid.");
    const completed = new Map<number, CustomPetStageDefinition>();
    for (const value of Array.isArray(raw.completedStages) ? raw.completedStages : []) {
      if (!isRecord(value) || !Number.isInteger(value.index)) throw new Error("Generation job stage is invalid.");
      const index = value.index as number;
      if (index < 0 || index >= request.stageNames.length) throw new Error("Generation job stage is out of range.");
      const stageID = boundedText(value.id, "Generation stage ID", 96);
      safeIdentifier(stageID);
      const expectedAsset = `stage-${String(index + 1).padStart(2, "0")}.png`;
      if (value.assetFileName !== expectedAsset || !Number.isFinite(value.experienceThreshold)) throw new Error("Generation job stage metadata is invalid.");
      if (!existsSync(this.processed(id, index))) continue;
      completed.set(index, {
        id: stageID,
        index,
        name: boundedText(value.name, "Generation stage name", 64),
        prompt: boundedText(value.prompt, "Generation stage prompt", 4_000),
        experienceThreshold: Math.max(0, value.experienceThreshold as number),
        assetFileName: expectedAsset
      });
    }
    return {
      schemaVersion: 1,
      id,
      templateID,
      state: raw.state as GenerationJob["state"],
      createdAt: validDate(raw.createdAt, "Generation job creation time"),
      updatedAt: validDate(raw.updatedAt, "Generation job update time"),
      request,
      completedStages: [...completed.values()].sort((a, b) => a.index - b.index),
      errorMessage: typeof raw.errorMessage === "string" ? raw.errorMessage.slice(0, 1_000) : null
    };
  }

  async loadAll(): Promise<GenerationJob[]> {
    await mkdir(this.paths.jobs, { recursive: true });
    const entries = await readdir(this.paths.jobs, { withFileTypes: true });
    const jobs = await Promise.all(entries.filter((entry) => entry.isDirectory()).map(async (entry) => {
      try { return await this.loadJob(entry.name); }
      catch { return undefined; }
    }));
    return jobs.filter((job): job is GenerationJob => Boolean(job)).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }

  async loadViews(): Promise<GenerationJobView[]> {
    return Promise.all((await this.loadAll()).map(async (job) => ({
      id: job.id,
      state: job.state,
      request: {
        templateName: job.request.templateName,
        quality: job.request.quality,
        stageNames: [...job.request.stageNames]
      },
      completedStageCount: job.completedStages.length,
      errorMessage: job.errorMessage,
      stageViews: job.request.stageNames.map((name, index) => {
        const raw = this.raw(job.id, index);
        const processed = this.processed(job.id, index);
        return {
          index,
          name,
          rawURL: existsSync(raw) ? mediaURL("jobs", job.id, path.basename(raw)) : undefined,
          processedURL: existsSync(processed) ? mediaURL("jobs", job.id, path.basename(processed)) : undefined,
          complete: job.completedStages.some((stage) => stage.index === index)
        };
      })
    })));
  }

  async create(request: StoredGenerationRequest): Promise<GenerationJob> {
    this.validateRequest(request);
    let reference: Buffer | undefined;
    if (request.referencePath) {
      const referenceInfo = await stat(request.referencePath);
      if (!referenceInfo.isFile() || referenceInfo.size < 32 || referenceInfo.size > MAX_REFERENCE_BYTES) throw new Error("Reference image size is invalid.");
      reference = await normalizeReference(await readFile(request.referencePath));
    }
    const id = randomUUID();
    const now = new Date().toISOString();
    const job: GenerationJob = {
      schemaVersion: 1,
      id,
      templateID: randomUUID(),
      state: "ready",
      createdAt: now,
      updatedAt: now,
      request: {
        ...request,
        referencePath: reference ? "reference.png" : undefined,
        stageNames: request.stageNames.map((name, index) => name.trim().slice(0, 32) || `Stage ${index + 1}`)
      },
      completedStages: [],
      errorMessage: null
    };
    try {
      await mkdir(this.directory(id), { recursive: true });
      if (reference) await atomicWrite(path.join(this.directory(id), "reference.png"), reference);
      await writeJSON(this.manifest(id), job);
      return job;
    } catch (error) {
      await rm(this.directory(id), { recursive: true, force: true });
      throw error;
    }
  }

  async run(
    jobID: string,
    apiKey: string,
    progress: (value: WorkshopProgress) => void
  ): Promise<CustomPetTemplate> {
    let job = await this.loadJob(jobID);
    if (!job) throw new Error("Generation job was not found.");
    if (this.activeJobID) throw new Error("Another generation job is already running.");
    if (!apiKey.trim() && job.request.stageNames.some((_, index) => !existsSync(this.raw(jobID, index)))) {
      throw new Error("The remaining stages require a new image request using your own OpenAI API key.");
    }
    this.activeJobID = jobID;
    this.cancelled = false;
    job.state = "running";
    job.updatedAt = new Date().toISOString();
    await writeJSON(this.manifest(jobID), job);
    const referencePath = path.join(this.directory(jobID), "reference.png");
    const reference = existsSync(referencePath) ? await readFile(referencePath) : undefined;
    const stageThresholds = thresholds(job.request.stageNames.length);
    const lineage: Buffer[] = [];

    try {
      for (const [index, name] of job.request.stageNames.entries()) {
        if (this.cancelled) throw new Error("Generation cancelled.");
        const prompt = this.prompt(job.request, index, name);
        const definition = this.definition(index, name, prompt, stageThresholds[index]!);
        progress({ jobID, completed: job.completedStages.length, total: job.request.stageNames.length, stageName: name, state: "running" });
        let raw: Buffer;
        if (existsSync(this.raw(jobID, index))) {
          raw = await readFile(this.raw(jobID, index));
        } else {
          if (!apiKey.trim()) throw new Error("The remaining stages require a new image request using your own OpenAI API key.");
          const inputs = [];
          if (reference) inputs.push({ data: reference, fileName: "original-reference.png" });
          if (lineage[0]) inputs.push({ data: lineage[0], fileName: "lineage-anchor.png" });
          if (lineage.length > 1) inputs.push({ data: lineage.at(-1)!, fileName: "previous-stage.png" });
          raw = inputs.length
            ? await this.client.edit(prompt, inputs, apiKey, job.request.quality)
            : await this.client.generate(prompt, apiKey, job.request.quality);
          await atomicWrite(this.raw(jobID, index), raw);
        }
        lineage.push(raw);
        if (!existsSync(this.processed(jobID, index))) {
          await atomicWrite(this.processed(jobID, index), await prepareGeneratedAsset(raw));
        }
        job.completedStages = [...job.completedStages.filter((stage) => stage.index !== index), definition].sort((a, b) => a.index - b.index);
        job.updatedAt = new Date().toISOString();
        await writeJSON(this.manifest(jobID), job);
        progress({ jobID, completed: job.completedStages.length, total: job.request.stageNames.length, stageName: name, state: "running" });
      }

      const template: CustomPetTemplate = {
        schemaVersion: 2,
        packFormat: "sidekin.pet-pack",
        minSidekinVersion: "2.2.0",
        id: job.templateID,
        name: job.request.templateName.trim(),
        author: "Local Sidekin user",
        license: "All rights reserved by the pack author",
        motionProfile: job.request.motionProfile ?? "poised",
        contentHashes: {},
        basePrompt: job.request.description.trim(),
        artDirection: job.request.artDirection.trim(),
        generationMode: job.request.mode,
        generationQuality: job.request.quality,
        referenceFileName: reference ? "reference.png" : null,
        createdAt: job.createdAt,
        fallbackTheme: job.request.fallbackTheme,
        stages: job.completedStages
      };
      const images = await Promise.all(template.stages.map((stage) => readFile(this.processed(jobID, stage.index))));
      const installed = await this.templates.install(template, images, reference);
      await rm(this.directory(jobID), { recursive: true, force: true });
      progress({ jobID, completed: images.length, total: images.length, stageName: "Installed", state: "complete" });
      return installed;
    } catch (error) {
      job = (await this.loadJob(jobID)) ?? job;
      job.state = this.cancelled ? "cancelled" : "failed";
      job.errorMessage = error instanceof Error ? error.message : String(error);
      job.updatedAt = new Date().toISOString();
      await writeJSON(this.manifest(jobID), job);
      progress({ jobID, completed: job.completedStages.length, total: job.request.stageNames.length, stageName: "Paused", state: job.state, message: job.errorMessage });
      throw error;
    } finally {
      this.activeJobID = undefined;
    }
  }

  cancel(): void { if (this.activeJobID) this.cancelled = true; }

  async requiresAPIKey(jobID: string): Promise<boolean> {
    const job = await this.loadJob(jobID);
    if (!job) throw new Error("Generation job was not found.");
    return job.request.stageNames.some((_, index) => !existsSync(this.raw(jobID, index)));
  }

  async reprocessJobStage(jobID: string, stageIndex: number): Promise<void> {
    const job = await this.loadJob(jobID);
    if (!job) throw new Error("Generation job was not found.");
    const name = job.request.stageNames[stageIndex];
    if (name === undefined) throw new Error("Generation stage is out of range.");
    const rawPath = this.raw(jobID, stageIndex);
    if (!existsSync(rawPath)) throw new Error("No paid raw image is saved for this stage.");
    await atomicWrite(this.processed(jobID, stageIndex), await prepareGeneratedAsset(await readFile(rawPath)));
    const prompt = this.prompt(job.request, stageIndex, name);
    const stageThresholds = thresholds(job.request.stageNames.length);
    const existing = job.completedStages.find((stage) => stage.index === stageIndex);
    const definition = existing ?? this.definition(stageIndex, name, prompt, stageThresholds[stageIndex]!);
    job.completedStages = [...job.completedStages.filter((stage) => stage.index !== stageIndex), definition].sort((a, b) => a.index - b.index);
    job.state = "ready";
    job.errorMessage = null;
    job.updatedAt = new Date().toISOString();
    await writeJSON(this.manifest(jobID), job);
  }

  async restartFromStage(jobID: string, stageIndex: number): Promise<void> {
    const job = await this.loadJob(jobID);
    if (!job) throw new Error("Generation job was not found.");
    if (!Number.isInteger(stageIndex) || stageIndex < 0 || stageIndex >= job.request.stageNames.length) throw new Error("Generation stage is out of range.");
    for (let index = stageIndex; index < job.request.stageNames.length; index += 1) {
      await rm(this.raw(jobID, index), { force: true });
      await rm(this.processed(jobID, index), { force: true });
    }
    job.completedStages = job.completedStages.filter((stage) => stage.index < stageIndex);
    job.state = "ready";
    job.errorMessage = null;
    job.updatedAt = new Date().toISOString();
    await writeJSON(this.manifest(jobID), job);
  }

  async replaceTemplateStage(templateID: string, stageIndex: number, input: Buffer): Promise<CustomPetTemplate> {
    const normalized = await normalizeReference(input);
    return this.templates.replaceStageImage(templateID, stageIndex, await prepareGeneratedAsset(normalized));
  }

  async regenerateTemplateStage(
    templateID: string,
    stageIndex: number,
    apiKey: string,
    progress: (value: WorkshopProgress) => void
  ): Promise<CustomPetTemplate> {
    if (!apiKey.trim()) throw new Error("Regenerating a stage requires your own OpenAI API key.");
    if (this.activeJobID) throw new Error("Another generation job is already running.");
    const template = await this.templates.load(templateID);
    if (!template) throw new Error("Template was not found.");
    const stage = template.stages[stageIndex];
    if (!stage) throw new Error("Template stage is out of range.");
    const operationID = `replace-${template.id}-${stageIndex}`;
    this.activeJobID = operationID;
    this.cancelled = false;
    const directory = path.dirname(this.templates.assetPath(template, 0));
    const inputs = [];
    if (template.referenceFileName) {
      const reference = path.join(directory, template.referenceFileName);
      if (existsSync(reference)) inputs.push({ data: await readFile(reference), fileName: "original-reference.png" });
    }
    for (const [label, index] of [["current-stage", stageIndex], ["previous-stage", stageIndex - 1], ["next-stage", stageIndex + 1]] as const) {
      if (index >= 0 && index < template.stages.length) inputs.push({ data: await readFile(this.templates.assetPath(template, index)), fileName: `${label}.png` });
    }
    const prompt = `Regenerate only stage ${stageIndex + 1} of ${template.stages.length} for the existing desktop-pet lineage ${template.name}. Concept: ${template.basePrompt}. Art direction: ${template.artDirection}. Stage name: ${stage.name}. Preserve the same nonhuman identity, lineage anchors, material system, palette, and neighboring-stage continuity while making this stage structurally distinct and readable at desktop-pet scale. One full-body character, centered, no text, no logo, no UI, no floor or shadow. Perfectly flat #FF00FF background.`;
    progress({ jobID: operationID, completed: 0, total: 1, stageName: stage.name, state: "running" });
    try {
      const raw = await this.client.edit(prompt, inputs, apiKey, template.generationQuality ?? "medium");
      const recovery = this.templates.recoveryPath(template.id, stageIndex);
      await atomicWrite(recovery, raw);
      if (this.cancelled) throw new Error("Generation cancelled after the paid image was saved locally.");
      const updated = await this.templates.replaceStageImage(template.id, stageIndex, await prepareGeneratedAsset(raw));
      await rm(recovery, { force: true });
      progress({ jobID: operationID, completed: 1, total: 1, stageName: stage.name, state: "complete" });
      return updated;
    } catch (error) {
      progress({ jobID: operationID, completed: 0, total: 1, stageName: stage.name, state: "failed", message: error instanceof Error ? error.message : String(error) });
      throw error;
    } finally {
      this.activeJobID = undefined;
    }
  }

  async reprocessTemplateRecovery(templateID: string, stageIndex: number): Promise<CustomPetTemplate> {
    const recovery = this.templates.recoveryPath(templateID, stageIndex);
    if (!existsSync(recovery)) throw new Error("No saved recovery image exists for this stage.");
    const updated = await this.templates.replaceStageImage(templateID, stageIndex, await prepareGeneratedAsset(await readFile(recovery)));
    await rm(recovery, { force: true });
    return updated;
  }

  private validateRequest(request: StoredGenerationRequest): void {
    boundedText(request.templateName, "Template name", 60);
    boundedText(request.description, "Description", 2_000);
    boundedText(request.artDirection, "Art direction", 1_000);
    if (!Array.isArray(request.stageNames) || request.stageNames.length < 1 || request.stageNames.length > 8) throw new Error("Use one to eight growth stages.");
    request.stageNames.forEach((name, index) => boundedText(name, `Stage ${index + 1}`, 64));
    if (!(["text", "restyle", "faithful"] as unknown[]).includes(request.mode)) throw new Error("The generation mode is invalid.");
    if (!(["low", "medium", "high"] as unknown[]).includes(request.quality)) throw new Error("The generation quality is invalid.");
    safeIdentifier(request.fallbackTheme);
    if (request.motionProfile && !/^[a-z-]{3,24}$/.test(request.motionProfile)) throw new Error("The motion profile is invalid.");
    if (request.mode !== "text" && !request.referencePath) throw new Error("This generation mode requires a reference image.");
  }

  private definition(
    index: number,
    name: string,
    prompt: string,
    experienceThreshold: number
  ): CustomPetStageDefinition {
    return {
      id: randomUUID(),
      index,
      name,
      prompt,
      experienceThreshold,
      assetFileName: `stage-${String(index + 1).padStart(2, "0")}.png`
    };
  }

  private prompt(request: StoredGenerationRequest, index: number, stageName: string): string {
    const total = request.stageNames.length;
    const position = total === 1 ? 1 : index / (total - 1);
    const maturity = position < 0.2 ? "compact origin form" : position < 0.45 ? "young readable form" : position < 0.7 ? "adolescent structural change" : position < 0.95 ? "advanced ability form" : "final apex silhouette";
    const mode = request.mode === "text"
      ? "Create an original species and preserve lineage anchors from earlier stages."
      : request.mode === "restyle"
        ? "Preserve the subject identity while deliberately restyling it."
        : "Preserve identity, markings, palette, proportions, and signature silhouette closely.";
    return `Generate exactly one full-body desktop pet asset, centered and inside frame. Template: ${request.templateName}. Concept: ${request.description}. Art direction: ${request.artDirection}. Stage ${index + 1} of ${total}, ${stageName}: ${maturity}. ${mode} Make body proportion, silhouette, pose, and stage anatomy genuinely different. One character, no text, no logo, no UI, no floor or cast shadow. Perfectly flat #FF00FF background.`;
  }
}
