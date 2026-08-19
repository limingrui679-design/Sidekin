import { existsSync } from "node:fs";
import AdmZip from "adm-zip";
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterEach, describe, expect, it } from "vitest";
import { prepareGeneratedAsset } from "../src/main/image-processor.js";
import type { ImageClient, ImageInput } from "../src/main/openai-client.js";
import type { SidekinPaths } from "../src/main/paths.js";
import { TemplateStore } from "../src/main/template-store.js";
import { WorkshopService } from "../src/main/workshop.js";
import type { GenerationQuality, GenerationRequest } from "../src/shared/types.js";

const temporaryDirectories: string[] = [];

async function testPaths(): Promise<SidekinPaths> {
  const root = await mkdtemp(path.join(tmpdir(), "sidekin-workshop-"));
  temporaryDirectories.push(root);
  return {
    userData: root,
    state: path.join(root, "pet-state.json"),
    settings: path.join(root, "settings.json"),
    eventInbox: path.join(root, "events.jsonl"),
    templates: path.join(root, "PetTemplates"),
    jobs: path.join(root, "GenerationJobs"),
    secret: path.join(root, "api-key.bin"),
    catalog: path.join(root, "catalog.json"),
    characters: path.join(root, "Characters"),
    thumbnails: path.join(root, "Thumbnails"),
    assetManifest: path.join(root, "manifest.json"),
    codexHooks: path.join(root, "hooks.json"),
    codexSessions: path.join(root, "sessions"),
    claudeSettings: path.join(root, "claude-settings.json")
  };
}

async function syntheticPet(): Promise<Buffer> {
  const body = Buffer.from(
    `<svg width="160" height="160" xmlns="http://www.w3.org/2000/svg">
      <rect width="160" height="160" fill="#ff00ff"/>
      <ellipse cx="80" cy="84" rx="48" ry="58" fill="#5b2ca0"/>
      <circle cx="80" cy="84" r="18" fill="#ff4faa"/>
      <circle cx="63" cy="67" r="5" fill="#ffffff"/>
      <circle cx="97" cy="67" r="5" fill="#ffffff"/>
    </svg>`
  );
  return sharp(body).png().toBuffer();
}

class InterruptOnceClient implements ImageClient {
  generateCalls = 0;
  editCalls = 0;
  private interrupted = false;
  constructor(private readonly image: Buffer) {}

  async generate(_prompt: string, _apiKey: string, _quality: GenerationQuality): Promise<Buffer> {
    this.generateCalls += 1;
    return this.image;
  }

  async edit(_prompt: string, _images: ImageInput[], _apiKey: string, _quality: GenerationQuality): Promise<Buffer> {
    this.editCalls += 1;
    if (!this.interrupted) {
      this.interrupted = true;
      throw new Error("simulated interruption");
    }
    return this.image;
  }
}

class StaticClient implements ImageClient {
  generateCalls = 0;
  editCalls = 0;
  constructor(private readonly image: Buffer) {}
  async generate(): Promise<Buffer> { this.generateCalls += 1; return this.image; }
  async edit(): Promise<Buffer> { this.editCalls += 1; return this.image; }
}

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("cross-platform Pet Workshop", () => {
  it("removes only edge-connected key color and preserves enclosed pink body detail", async () => {
    const result = await prepareGeneratedAsset(await syntheticPet());
    const { data, info } = await sharp(result).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    expect([info.width, info.height]).toEqual([1_254, 1_254]);
    const alphaAt = (x: number, y: number) => data[(y * info.width + x) * 4 + 3];
    expect(alphaAt(0, 0)).toBe(0);
    expect(alphaAt(Math.floor(info.width / 2), Math.floor(info.height / 2))).toBeGreaterThan(200);
    let preservedPink = 0;
    for (let offset = 0; offset < data.length; offset += 4) {
      if (data[offset]! > 220 && data[offset + 1]! < 130 && data[offset + 2]! > 120 && data[offset + 3]! > 200) preservedPink += 1;
    }
    expect(preservedPink).toBeGreaterThan(500);
  });

  it("resumes after a failed paid stage without requesting the saved first stage again", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const client = new InterruptOnceClient(await syntheticPet());
    const workshop = new WorkshopService(paths, templates, client);
    const request: GenerationRequest = {
      templateName: "Continuity Test",
      description: "A nonhuman crystal sentinel",
      artDirection: "polished game mascot",
      mode: "text",
      quality: "low",
      stageNames: ["Origin", "Awakened", "Crown"],
      fallbackTheme: "nova"
    };
    const job = await workshop.create(request);
    await expect(workshop.run(job.id, "user-owned-test-key", () => undefined)).rejects.toThrow("simulated interruption");
    expect(client.generateCalls).toBe(1);
    expect(existsSync(path.join(paths.jobs, job.id, "raw-stage-01.png"))).toBe(true);
    const paused = JSON.parse(await readFile(path.join(paths.jobs, job.id, "job.json"), "utf8"));
    expect(paused.completedStages).toHaveLength(1);
    const views = await workshop.loadViews();
    expect(views[0]?.stageViews[0]).toMatchObject({ complete: true });
    expect(views[0]?.stageViews[0]?.rawURL).toMatch(/^sidekin-media:\/\/jobs\//);
    expect(views[0]?.stageViews[0]?.processedURL).toMatch(/^sidekin-media:\/\/jobs\//);
    expect(views[0]?.stageViews[0]?.rawURL).not.toContain(paths.userData);

    const installed = await workshop.run(job.id, "user-owned-test-key", () => undefined);
    expect(client.generateCalls).toBe(1);
    expect(client.editCalls).toBe(3);
    expect(installed.stages).toHaveLength(3);
    expect(existsSync(path.join(paths.templates, installed.id, "stage-03.png"))).toBe(true);
    expect(existsSync(path.join(paths.jobs, job.id))).toBe(false);
  });

  it("processes a fully saved job locally without requiring an API key", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const image = await syntheticPet();
    const client = new StaticClient(image);
    const workshop = new WorkshopService(paths, templates, client);
    const job = await workshop.create({
      templateName: "Offline Finish",
      description: "A saved nonhuman pet",
      artDirection: "game mascot",
      mode: "text",
      quality: "low",
      stageNames: ["Origin", "Crown"],
      fallbackTheme: "nova"
    });
    await writeFile(path.join(paths.jobs, job.id, "raw-stage-01.png"), image);
    await writeFile(path.join(paths.jobs, job.id, "raw-stage-02.png"), image);
    const installed = await workshop.run(job.id, "", () => undefined);
    expect(installed.stages).toHaveLength(2);
    expect(client.generateCalls + client.editCalls).toBe(0);
  });

  it("rejects a missing API key before mutating a job that still needs paid requests", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const workshop = new WorkshopService(paths, templates, new StaticClient(await syntheticPet()));
    const job = await workshop.create({ templateName: "No Key", description: "A local pet", artDirection: "game mascot", mode: "text", quality: "low", stageNames: ["Origin"], fallbackTheme: "nova" });
    await expect(workshop.run(job.id, "", () => undefined)).rejects.toThrow(/API key/i);
    const persisted = JSON.parse(await readFile(path.join(paths.jobs, job.id, "job.json"), "utf8"));
    expect(persisted).toMatchObject({ state: "ready", errorMessage: null });
    expect(await workshop.requiresAPIKey(job.id)).toBe(true);
    await mkdir(path.join(paths.jobs, "corrupt-job"), { recursive: true });
    await writeFile(path.join(paths.jobs, "corrupt-job", "job.json"), "{broken");
    expect((await workshop.loadAll()).map((value) => value.id)).toEqual([job.id]);
  });

  it("copies a selected reference without persisting its original machine path", async () => {
    const paths = await testPaths();
    const referencePath = path.join(paths.userData, "private-reference-name.png");
    await writeFile(referencePath, await syntheticPet());
    const templates = new TemplateStore(paths);
    const workshop = new WorkshopService(paths, templates, new StaticClient(await syntheticPet()));
    const job = await workshop.create({ templateName: "Private Path", description: "A local pet", artDirection: "game mascot", mode: "faithful", quality: "low", stageNames: ["Origin"], fallbackTheme: "nova", referencePath });
    const source = await readFile(path.join(paths.jobs, job.id, "job.json"), "utf8");
    expect(source).not.toContain(referencePath);
    expect(source).not.toContain("private-reference-name.png");
    expect(JSON.parse(source).request.referencePath).toBe("reference.png");
  });

  it("can clear recovery from a selected stage without touching earlier paid files", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const image = await syntheticPet();
    const client = new StaticClient(image);
    const workshop = new WorkshopService(paths, templates, client);
    const job = await workshop.create({ templateName: "Restart", description: "test pet", artDirection: "test", mode: "text", quality: "low", stageNames: ["One", "Two", "Three"], fallbackTheme: "nova" });
    for (let index = 0; index < 3; index += 1) await writeFile(path.join(paths.jobs, job.id, `raw-stage-0${index + 1}.png`), image);
    await workshop.reprocessJobStage(job.id, 0);
    await workshop.reprocessJobStage(job.id, 1);
    await workshop.restartFromStage(job.id, 1);
    expect(existsSync(path.join(paths.jobs, job.id, "raw-stage-01.png"))).toBe(true);
    expect(existsSync(path.join(paths.jobs, job.id, "raw-stage-02.png"))).toBe(false);
    expect(existsSync(path.join(paths.jobs, job.id, "raw-stage-03.png"))).toBe(false);
    const restarted = (await workshop.loadAll())[0]!;
    expect(restarted.completedStages.map((stage) => stage.index)).toEqual([0]);
  });

  it("replaces one installed stage and retains a paid raw recovery if cutout processing fails", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const raw = await syntheticPet();
    const processed = await prepareGeneratedAsset(raw);
    const manifest = {
      schemaVersion: 1 as const,
      id: "stage-replacement",
      name: "Stage Replacement",
      basePrompt: "A crystal sentinel",
      artDirection: "premium game mascot",
      generationMode: "text" as const,
      generationQuality: "low" as const,
      createdAt: new Date(0).toISOString(),
      fallbackTheme: "nova",
      stages: [
        { id: "one", index: 0, name: "Origin", prompt: "origin", experienceThreshold: 0, assetFileName: "stage-01.png" },
        { id: "two", index: 1, name: "Crown", prompt: "crown", experienceThreshold: 20, assetFileName: "stage-02.png" }
      ]
    };
    await templates.install(manifest, [processed, processed]);
    const badClient = new StaticClient(Buffer.from("paid but corrupt image"));
    const workshop = new WorkshopService(paths, templates, badClient);
    await expect(workshop.regenerateTemplateStage(manifest.id, 1, "user-owned-test-key", () => undefined)).rejects.toThrow(/image|input|format/i);
    const recovery = templates.recoveryPath(manifest.id, 1);
    expect(existsSync(recovery)).toBe(true);
    expect((await templates.loadViews())[0]?.stageViews[1]?.recoveryRawURL).toMatch(/^sidekin-media:\/\/templates\//);
    expect((await templates.loadViews())[0]?.stageViews[1]?.recoveryRawURL).not.toContain(paths.userData);
    await writeFile(recovery, raw);
    await workshop.reprocessTemplateRecovery(manifest.id, 1);
    expect(existsSync(recovery)).toBe(false);
    await workshop.replaceTemplateStage(manifest.id, 0, raw);
    const metadata = await sharp(await readFile(templates.assetPath(manifest, 0))).metadata();
    expect([metadata.width, metadata.height]).toEqual([1_254, 1_254]);
  });

  it("rejects corrupt images before installing a local template", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    await expect(templates.install({
      schemaVersion: 1,
      id: "corrupt-test",
      name: "Corrupt Test",
      basePrompt: "test",
      artDirection: "test",
      generationMode: "text",
      generationQuality: "low",
      createdAt: new Date(0).toISOString(),
      fallbackTheme: "nova",
      stages: [{ id: "stage-1", index: 0, name: "Stage", prompt: "test", experienceThreshold: 0, assetFileName: "stage-01.png" }]
    }, [Buffer.from("not a png")])).rejects.toThrow(/image/i);
  });

  it("requires transparent stage assets while allowing an opaque reference image", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const opaque = await sharp({ create: { width: 96, height: 96, channels: 3, background: "#334455" } }).png().toBuffer();
    const transparent = await sharp({ create: { width: 96, height: 96, channels: 4, background: "#334455ff" } }).png().toBuffer();
    const manifest = {
      schemaVersion: 1 as const,
      id: "alpha-boundary",
      name: "Alpha Boundary",
      basePrompt: "A local test familiar",
      artDirection: "game mascot",
      generationMode: "faithful" as const,
      generationQuality: "low" as const,
      referenceFileName: "reference.png",
      createdAt: new Date(0).toISOString(),
      fallbackTheme: "nova",
      stages: [{ id: "origin", index: 0, name: "Origin", prompt: "origin", experienceThreshold: 0, assetFileName: "stage-01.png" }]
    };
    await expect(templates.install(manifest, [opaque], opaque)).rejects.toThrow(/alpha channel/i);
    await expect(templates.install(manifest, [transparent], opaque)).resolves.toMatchObject({ id: "alpha-boundary" });
  });

  it("recovers an interrupted atomic template replacement and skips corrupt siblings", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const image = await prepareGeneratedAsset(await syntheticPet());
    const manifest = {
      schemaVersion: 1 as const,
      id: "atomic-recovery",
      name: "Atomic Recovery",
      basePrompt: "A local test familiar",
      artDirection: "game mascot",
      generationMode: "text" as const,
      generationQuality: "low" as const,
      createdAt: new Date(0).toISOString(),
      fallbackTheme: "nova",
      stages: [{ id: "origin", index: 0, name: "Origin", prompt: "origin", experienceThreshold: 0, assetFileName: "stage-01.png" }]
    };
    await templates.install(manifest, [image]);
    await rename(path.join(paths.templates, manifest.id), path.join(paths.templates, `.sidekin-backup-${manifest.id}`));
    await mkdir(path.join(paths.templates, `.sidekin-install-${manifest.id}`), { recursive: true });
    await mkdir(path.join(paths.templates, "corrupt-sibling"), { recursive: true });
    await writeFile(path.join(paths.templates, "corrupt-sibling", "template.json"), "{broken");

    const loaded = await templates.loadAll();
    expect(loaded.map((template) => template.id)).toEqual([manifest.id]);
    expect(existsSync(path.join(paths.templates, manifest.id, "stage-01.png"))).toBe(true);
    expect(existsSync(path.join(paths.templates, `.sidekin-install-${manifest.id}`))).toBe(false);
  });

  it("rejects undeclared files and packs that require a newer Sidekin version", async () => {
    const paths = await testPaths();
    const templates = new TemplateStore(paths);
    const image = await prepareGeneratedAsset(await syntheticPet());
    await templates.install({
      schemaVersion: 1,
      id: "import-boundary",
      name: "Import Boundary",
      basePrompt: "A local test familiar",
      artDirection: "game mascot",
      generationMode: "text",
      generationQuality: "low",
      createdAt: new Date(0).toISOString(),
      fallbackTheme: "nova",
      stages: [{ id: "origin", index: 0, name: "Origin", prompt: "origin", experienceThreshold: 0, assetFileName: "stage-01.png" }]
    }, [image]);
    const packed = await templates.exportPackage("import-boundary");
    const withExtra = new AdmZip(packed);
    withExtra.addFile("payload.js", Buffer.from("not executable, but still undeclared"));
    await expect(templates.importPackage(withExtra.toBuffer())).rejects.toThrow(/undeclared/i);

    const future = new AdmZip(packed);
    const manifest = JSON.parse(future.getEntry("template.json")!.getData().toString("utf8"));
    manifest.minSidekinVersion = "99.0.0";
    future.updateFile("template.json", Buffer.from(`${JSON.stringify(manifest)}\n`));
    await expect(templates.importPackage(future.toBuffer())).rejects.toThrow(/requires Sidekin 99\.0\.0/i);
  });
});
