import AdmZip from "adm-zip";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rename, rm } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";
import type { CustomPetTemplate, CustomPetTemplateView } from "../shared/types.js";
import { mediaURL } from "../shared/media.js";
import type { SidekinPaths } from "./paths.js";
import { atomicWrite, readJSON, safeFileName, safeIdentifier, writeJSON } from "./file-store.js";

const MAX_PACKAGE_BYTES = 96 * 1024 * 1024;
const MAX_ENTRY_BYTES = 20 * 1024 * 1024;
const MAX_MANIFEST_BYTES = 1024 * 1024;
const PET_PACK_SCHEMA = 2;
const PET_PACK_FORMAT = "sidekin.pet-pack" as const;
const MIN_SIDEKIN_VERSION = "2.2.0";
const MOTION_PROFILES = new Set(["agile", "bouncing", "buoyant", "flowing", "gliding", "heavy", "marching", "mechanical", "orbiting", "poised", "prowling", "pulsing", "rolling", "rooted", "serpentine", "skittering", "spectral", "swarming", "swimming", "winged"]);

function sha256(value: Buffer): string { return createHash("sha256").update(value).digest("hex"); }
function versionParts(value: string): number[] { return value.split(".").map(Number); }
function newerThanSupported(value: string): boolean {
  const candidate = versionParts(value);
  const supported = versionParts(MIN_SIDEKIN_VERSION);
  for (let index = 0; index < 3; index += 1) {
    if (candidate[index] !== supported[index]) return candidate[index]! > supported[index]!;
  }
  return false;
}

export class TemplateStore {
  private readonly installing = new Set<string>();

  constructor(private readonly paths: SidekinPaths) {}

  private directory(id: string): string {
    return path.join(this.paths.templates, safeIdentifier(id));
  }

  async loadAll(): Promise<CustomPetTemplate[]> {
    await mkdir(this.paths.templates, { recursive: true });
    await this.recoverInterruptedInstalls();
    const entries = await readdir(this.paths.templates, { withFileTypes: true });
    const templates = await Promise.all(entries
      .filter((entry) => entry.isDirectory() && !entry.name.startsWith(".sidekin-"))
      .map(async (entry) => {
        try { return await this.load(entry.name); }
        catch { return undefined; }
      }));
    return templates.filter((value): value is CustomPetTemplate => Boolean(value)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async loadViews(): Promise<CustomPetTemplateView[]> {
    return Promise.all((await this.loadAll()).map((template) => this.view(template)));
  }

  async load(id: string): Promise<CustomPetTemplate | undefined> {
    const raw = await readJSON<CustomPetTemplate>(path.join(this.directory(id), "template.json"));
    if (!raw) return undefined;
    const template = this.normalize(raw);
    this.validate(template);
    for (const stage of template.stages) {
      if (!existsSync(path.join(this.directory(id), safeFileName(stage.assetFileName)))) throw new Error(`Template image ${stage.assetFileName} is missing.`);
    }
    if (template.referenceFileName && !existsSync(path.join(this.directory(id), safeFileName(template.referenceFileName)))) throw new Error("Template reference image is missing.");
    if (raw.schemaVersion !== PET_PACK_SCHEMA) await writeJSON(path.join(this.directory(id), "template.json"), template);
    return template;
  }

  assetPath(template: CustomPetTemplate, stageIndex: number): string {
    const stage = template.stages[stageIndex];
    if (!stage) throw new Error("Template stage is out of range.");
    return path.join(this.directory(template.id), safeFileName(stage.assetFileName));
  }

  recoveryPath(templateID: string, stageIndex: number): string {
    return path.join(this.directory(templateID), `recovery-stage-${String(stageIndex + 1).padStart(2, "0")}.png`);
  }

  async view(template: CustomPetTemplate): Promise<CustomPetTemplateView> {
    return {
      id: template.id,
      name: template.name,
      author: template.author,
      license: template.license,
      motionProfile: template.motionProfile,
      generationQuality: template.generationQuality,
      createdAt: template.createdAt,
      stages: template.stages.map((stage) => ({
        index: stage.index,
        name: stage.name,
        experienceThreshold: stage.experienceThreshold,
        assetFileName: stage.assetFileName
      })),
      stageViews: template.stages.map((stage, index) => {
        const recovery = this.recoveryPath(template.id, index);
        return {
          index,
          assetURL: mediaURL("templates", template.id, stage.assetFileName),
          recoveryRawURL: existsSync(recovery) ? mediaURL("templates", template.id, path.basename(recovery)) : undefined
        };
      })
    };
  }

  async install(template: CustomPetTemplate, images: Buffer[], reference?: Buffer): Promise<CustomPetTemplate> {
    const normalized = this.normalize(template);
    this.validate(normalized);
    await this.recoverInterruptedInstalls();
    if (this.installing.has(normalized.id)) throw new Error("This template is already being installed.");
    this.installing.add(normalized.id);
    const temporary = path.join(this.paths.templates, `.sidekin-install-${normalized.id}`);
    try {
      if (Boolean(normalized.referenceFileName) !== Boolean(reference)) throw new Error("Pet Pack reference metadata and image must match.");
      if (images.length !== normalized.stages.length) throw new Error("Every stage needs one image.");
      await Promise.all(images.map((image) => this.validateImage(image)));
      if (reference) await this.validateImage(reference, false);
      const prepared = this.withHashes(normalized, images, reference);
      const target = this.directory(prepared.id);
      const backup = path.join(this.paths.templates, `.sidekin-backup-${prepared.id}`);
      await rm(temporary, { recursive: true, force: true });
      await mkdir(temporary, { recursive: true });
      for (const [index, stage] of prepared.stages.entries()) {
        await atomicWrite(path.join(temporary, safeFileName(stage.assetFileName)), images[index]!);
      }
      if (reference && prepared.referenceFileName) {
        await atomicWrite(path.join(temporary, safeFileName(prepared.referenceFileName)), reference);
      }
      await writeJSON(path.join(temporary, "template.json"), prepared);
      await rm(backup, { recursive: true, force: true });
      const hadTarget = existsSync(target);
      if (hadTarget) await rename(target, backup);
      try {
        await rename(temporary, target);
      } catch (error) {
        if (hadTarget && !existsSync(target) && existsSync(backup)) await rename(backup, target);
        throw error;
      }
      try { await rm(backup, { recursive: true, force: true }); } catch { /* committed target remains valid */ }
      return prepared;
    } finally {
      await rm(temporary, { recursive: true, force: true });
      this.installing.delete(normalized.id);
    }
  }

  async rename(id: string, rawName: string): Promise<CustomPetTemplate> {
    const template = await this.load(id);
    if (!template) throw new Error("Template was not found.");
    const name = rawName.trim().slice(0, 60);
    if (!name) throw new Error("Template name cannot be empty.");
    template.name = name;
    await writeJSON(path.join(this.directory(id), "template.json"), template);
    return template;
  }

  async replaceStageImage(id: string, stageIndex: number, image: Buffer): Promise<CustomPetTemplate> {
    const template = await this.load(id);
    if (!template) throw new Error("Template was not found.");
    await this.validateImage(image);
    await atomicWrite(this.assetPath(template, stageIndex), image);
    template.contentHashes = { ...template.contentHashes, [template.stages[stageIndex]!.assetFileName]: sha256(image) };
    await writeJSON(path.join(this.directory(id), "template.json"), template);
    return template;
  }

  async remove(id: string): Promise<void> {
    await rm(this.directory(id), { recursive: true, force: true });
  }

  async exportPackage(id: string): Promise<Buffer> {
    const template = await this.load(id);
    if (!template) throw new Error("Template was not found.");
    const zip = new AdmZip();
    const directory = this.directory(id);
    const images = await Promise.all(template.stages.map((stage) => readFile(path.join(directory, safeFileName(stage.assetFileName)))));
    const referencePath = template.referenceFileName ? path.join(directory, safeFileName(template.referenceFileName)) : undefined;
    if (referencePath && !existsSync(referencePath)) throw new Error("Pet Pack reference image is missing.");
    const reference = referencePath ? await readFile(referencePath) : undefined;
    const prepared = this.withHashes(template, images, reference);
    await writeJSON(path.join(directory, "template.json"), prepared);
    zip.addFile("template.json", Buffer.from(`${JSON.stringify(prepared, null, 2)}\n`));
    for (const [index, stage] of prepared.stages.entries()) zip.addFile(stage.assetFileName, images[index]!);
    if (reference && prepared.referenceFileName) zip.addFile(prepared.referenceFileName, reference);
    const data = zip.toBuffer();
    if (data.length > MAX_PACKAGE_BYTES) throw new Error("Template package is too large.");
    return data;
  }

  async importPackage(data: Buffer): Promise<CustomPetTemplate> {
    if (data.length > MAX_PACKAGE_BYTES) throw new Error("Template package is too large.");
    const zip = new AdmZip(data);
    const entries = zip.getEntries();
    const names = new Set<string>();
    const entryNames: string[] = [];
    let expandedBytes = 0;
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      const normalizedName = entry.entryName.toLowerCase();
      if (names.has(normalizedName)) throw new Error("Template package contains duplicate entries.");
      names.add(normalizedName);
      entryNames.push(entry.entryName);
      if (!Number.isFinite(entry.header.size) || entry.header.size < 0) throw new Error("Template package contains an invalid entry size.");
      expandedBytes += entry.header.size;
      const entryLimit = entry.entryName === "template.json" ? MAX_MANIFEST_BYTES : MAX_ENTRY_BYTES;
      if (entry.entryName !== safeFileName(entry.entryName) || entry.header.size > entryLimit) {
        throw new Error("Template package contains an unsafe entry.");
      }
    }
    if (expandedBytes > MAX_PACKAGE_BYTES) throw new Error("Expanded template package is too large.");
    const manifest = zip.getEntry("template.json");
    if (!manifest) throw new Error("Template manifest is missing.");
    const manifestData = manifest.getData();
    if (manifestData.length > MAX_MANIFEST_BYTES) throw new Error("Template manifest is too large.");
    let raw: CustomPetTemplate;
    try { raw = JSON.parse(manifestData.toString("utf8")) as CustomPetTemplate; }
    catch { throw new Error("Template manifest is not valid JSON."); }
    const template = this.normalize(raw);
    this.validate(template);
    const allowed = new Set(["template.json", ...template.stages.map((stage) => stage.assetFileName), ...(template.referenceFileName ? [template.referenceFileName] : [])]);
    const unexpected = entryNames.filter((name) => !allowed.has(name));
    if (unexpected.length) throw new Error(`Template package contains undeclared entries: ${unexpected.join(", ")}.`);
    const images = template.stages.map((stage) => {
      const entry = zip.getEntry(safeFileName(stage.assetFileName));
      if (!entry) throw new Error(`Missing ${stage.assetFileName}.`);
      return entry.getData();
    });
    const referenceEntry = template.referenceFileName ? zip.getEntry(safeFileName(template.referenceFileName)) : undefined;
    if (template.referenceFileName && !referenceEntry) throw new Error(`Missing ${template.referenceFileName}.`);
    const reference = referenceEntry?.getData();
    if (raw.schemaVersion === PET_PACK_SCHEMA) this.verifyHashes(template, images, reference);
    return this.install(template, images, reference);
  }

  validate(template: CustomPetTemplate): void {
    safeIdentifier(template.id);
    if (template.schemaVersion !== PET_PACK_SCHEMA || template.packFormat !== PET_PACK_FORMAT) throw new Error("Unsupported Pet Pack schema version.");
    if (!template.name.trim() || template.stages.length < 1 || template.stages.length > 8) {
      throw new Error("Template must have a name and one to eight stages.");
    }
    if (template.name.length > 60 || !template.basePrompt?.trim() || template.basePrompt.length > 2_000 || !template.artDirection?.trim() || template.artDirection.length > 1_000) throw new Error("Template metadata is missing or too long.");
    if (!template.author?.trim() || template.author.length > 120 || !template.license?.trim() || template.license.length > 160) throw new Error("Pet Pack author and license are required.");
    if (!Number.isFinite(new Date(template.createdAt).getTime())) throw new Error("Pet Pack creation time is invalid.");
    if (!template.motionProfile || !MOTION_PROFILES.has(template.motionProfile)) throw new Error("Pet Pack motion profile is unsupported.");
    if (!template.minSidekinVersion || !/^\d+\.\d+\.\d+$/.test(template.minSidekinVersion)) throw new Error("Pet Pack minimum Sidekin version is invalid.");
    if (newerThanSupported(template.minSidekinVersion)) throw new Error(`Pet Pack requires Sidekin ${template.minSidekinVersion} or newer.`);
    if (!(["text", "restyle", "faithful"] as string[]).includes(template.generationMode)) throw new Error("Pet Pack generation mode is invalid.");
    if (template.generationQuality && !["low", "medium", "high"].includes(template.generationQuality)) throw new Error("Pet Pack generation quality is invalid.");
    safeIdentifier(template.fallbackTheme);
    const indexes = new Set<number>();
    const assetNames = new Set<string>();
    let previousThreshold = -1;
    for (const [position, stage] of template.stages.entries()) {
      safeFileName(stage.assetFileName);
      safeIdentifier(stage.id);
      if (indexes.has(stage.index)) throw new Error("Template stage indexes must be unique.");
      if (assetNames.has(stage.assetFileName.toLowerCase())) throw new Error("Template stage asset names must be unique.");
      if (stage.index !== position || !stage.name?.trim() || stage.name.length > 64 || !stage.prompt?.trim() || stage.prompt.length > 4_000) throw new Error("Pet Pack stages must be ordered and complete.");
      if (!Number.isFinite(stage.experienceThreshold) || stage.experienceThreshold < previousThreshold) throw new Error("Pet Pack growth thresholds must be monotonic.");
      if (position === 0 && stage.experienceThreshold !== 0) throw new Error("The first Pet Pack growth threshold must be zero.");
      if (!stage.assetFileName.toLowerCase().endsWith(".png")) throw new Error("Pet Pack stage assets must be PNG files.");
      previousThreshold = stage.experienceThreshold;
      indexes.add(stage.index);
      assetNames.add(stage.assetFileName.toLowerCase());
    }
    if (template.referenceFileName) {
      safeFileName(template.referenceFileName);
      if (!template.referenceFileName.toLowerCase().endsWith(".png") || assetNames.has(template.referenceFileName.toLowerCase())) throw new Error("Pet Pack reference image must be a unique PNG file.");
    }
    for (const [file, hash] of Object.entries(template.contentHashes ?? {})) {
      safeFileName(file);
      if (!/^[a-f0-9]{64}$/.test(hash)) throw new Error("Pet Pack content hash is invalid.");
    }
  }

  private normalize(template: CustomPetTemplate): CustomPetTemplate {
    if (typeof template !== "object" || template === null || Array.isArray(template)) throw new Error("Pet Pack manifest must be a JSON object.");
    const stages = Array.isArray(template.stages) && template.stages.every((stage) => typeof stage === "object" && stage !== null && !Array.isArray(stage))
      ? [...template.stages].sort((a, b) => a.index - b.index)
      : [];
    return {
      ...template,
      schemaVersion: PET_PACK_SCHEMA,
      packFormat: PET_PACK_FORMAT,
      minSidekinVersion: template.minSidekinVersion ?? MIN_SIDEKIN_VERSION,
      author: template.author?.trim() || "Local Sidekin user",
      license: template.license?.trim() || "All rights reserved by the pack author",
      motionProfile: template.motionProfile && MOTION_PROFILES.has(template.motionProfile) ? template.motionProfile : "poised",
      contentHashes: template.contentHashes,
      stages
    };
  }

  private withHashes(template: CustomPetTemplate, images: Buffer[], reference?: Buffer): CustomPetTemplate {
    const contentHashes: Record<string, string> = {};
    template.stages.forEach((stage, index) => { contentHashes[stage.assetFileName] = sha256(images[index]!); });
    if (reference && template.referenceFileName) contentHashes[template.referenceFileName] = sha256(reference);
    return { ...template, contentHashes };
  }

  private verifyHashes(template: CustomPetTemplate, images: Buffer[], reference?: Buffer): void {
    const expected = this.withHashes(template, images, reference).contentHashes ?? {};
    const actual = template.contentHashes ?? {};
    if (Object.keys(expected).length !== Object.keys(actual).length || Object.entries(expected).some(([file, hash]) => actual[file] !== hash)) {
      throw new Error("Pet Pack content hashes do not match its files.");
    }
  }

  private async validateImage(image: Buffer, requireAlpha = true): Promise<void> {
    if (image.length < 32 || image.length > MAX_ENTRY_BYTES) throw new Error("Template image size is invalid.");
    let metadata: sharp.Metadata;
    try { metadata = await sharp(image, { failOn: "error" }).metadata(); } catch { throw new Error("Template contains a corrupt image."); }
    if (metadata.format !== "png" || !metadata.width || !metadata.height || metadata.width < 32 || metadata.height < 32 || metadata.width > 4_096 || metadata.height > 4_096) {
      throw new Error("Template images must be valid PNG files between 32 and 4096 pixels.");
    }
    if (requireAlpha && !metadata.hasAlpha) throw new Error("Template stage images must include an alpha channel for desktop transparency.");
  }

  private async recoverInterruptedInstalls(): Promise<void> {
    await mkdir(this.paths.templates, { recursive: true });
    const entries = await readdir(this.paths.templates, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory() || !entry.name.startsWith(".sidekin-backup-")) continue;
      const id = entry.name.slice(".sidekin-backup-".length);
      try { safeIdentifier(id); } catch { continue; }
      if (this.installing.has(id)) continue;
      const backup = path.join(this.paths.templates, entry.name);
      const target = this.directory(id);
      if (existsSync(target)) await rm(backup, { recursive: true, force: true });
      else await rename(backup, target);
    }
    for (const entry of await readdir(this.paths.templates, { withFileTypes: true })) {
      if (!entry.isDirectory() || !entry.name.startsWith(".sidekin-install-")) continue;
      const id = entry.name.slice(".sidekin-install-".length);
      try { safeIdentifier(id); } catch { continue; }
      if (this.installing.has(id)) continue;
      await rm(path.join(this.paths.templates, entry.name), { recursive: true, force: true });
    }
  }
}
