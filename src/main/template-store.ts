import AdmZip from "adm-zip";
import { existsSync } from "node:fs";
import { cp, mkdir, readFile, readdir, rm } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import sharp from "sharp";
import type { CustomPetTemplate, CustomPetTemplateView } from "../shared/types.js";
import type { SidekinPaths } from "./paths.js";
import { atomicWrite, readJSON, safeFileName, safeIdentifier, writeJSON } from "./file-store.js";

const MAX_PACKAGE_BYTES = 96 * 1024 * 1024;
const MAX_ENTRY_BYTES = 20 * 1024 * 1024;

export class TemplateStore {
  constructor(private readonly paths: SidekinPaths) {}

  private directory(id: string): string {
    return path.join(this.paths.templates, safeIdentifier(id));
  }

  async loadAll(): Promise<CustomPetTemplate[]> {
    await mkdir(this.paths.templates, { recursive: true });
    const entries = await readdir(this.paths.templates, { withFileTypes: true });
    const templates = await Promise.all(entries.filter((entry) => entry.isDirectory()).map((entry) => this.load(entry.name)));
    return templates.filter((value): value is CustomPetTemplate => Boolean(value)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async loadViews(): Promise<CustomPetTemplateView[]> {
    return Promise.all((await this.loadAll()).map((template) => this.view(template)));
  }

  async load(id: string): Promise<CustomPetTemplate | undefined> {
    const manifest = await readJSON<CustomPetTemplate>(path.join(this.directory(id), "template.json"));
    if (!manifest) return undefined;
    this.validate(manifest);
    return manifest;
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
      ...template,
      stageViews: template.stages.map((stage, index) => {
        const recovery = this.recoveryPath(template.id, index);
        return {
          index,
          assetURL: pathToFileURL(this.assetPath(template, index)).href,
          recoveryRawURL: existsSync(recovery) ? pathToFileURL(recovery).href : undefined
        };
      })
    };
  }

  async install(template: CustomPetTemplate, images: Buffer[], reference?: Buffer): Promise<CustomPetTemplate> {
    this.validate(template);
    if (images.length !== template.stages.length) throw new Error("Every stage needs one image.");
    await Promise.all(images.map((image) => this.validateImage(image)));
    const target = this.directory(template.id);
    const temporary = `${target}.install-${Date.now()}`;
    await rm(temporary, { recursive: true, force: true });
    await mkdir(temporary, { recursive: true });
    try {
      for (const [index, stage] of template.stages.entries()) {
        await atomicWrite(path.join(temporary, safeFileName(stage.assetFileName)), images[index]!);
      }
      if (reference && template.referenceFileName) {
        await atomicWrite(path.join(temporary, safeFileName(template.referenceFileName)), reference);
      }
      await writeJSON(path.join(temporary, "template.json"), template);
      await rm(target, { recursive: true, force: true });
      await cp(temporary, target, { recursive: true });
      return template;
    } finally {
      await rm(temporary, { recursive: true, force: true });
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
    zip.addFile("template.json", Buffer.from(`${JSON.stringify(template, null, 2)}\n`));
    for (const stage of template.stages) {
      zip.addFile(stage.assetFileName, await readFile(path.join(directory, safeFileName(stage.assetFileName))));
    }
    if (template.referenceFileName) {
      const reference = path.join(directory, safeFileName(template.referenceFileName));
      if (existsSync(reference)) zip.addFile(template.referenceFileName, await readFile(reference));
    }
    const data = zip.toBuffer();
    if (data.length > MAX_PACKAGE_BYTES) throw new Error("Template package is too large.");
    return data;
  }

  async importPackage(data: Buffer): Promise<CustomPetTemplate> {
    if (data.length > MAX_PACKAGE_BYTES) throw new Error("Template package is too large.");
    const zip = new AdmZip(data);
    const entries = zip.getEntries();
    for (const entry of entries) {
      if (entry.isDirectory) continue;
      if (entry.entryName !== safeFileName(entry.entryName) || entry.header.size > MAX_ENTRY_BYTES) {
        throw new Error("Template package contains an unsafe entry.");
      }
    }
    const manifest = zip.getEntry("template.json");
    if (!manifest) throw new Error("Template manifest is missing.");
    const template = JSON.parse(manifest.getData().toString("utf8")) as CustomPetTemplate;
    this.validate(template);
    const images = template.stages.map((stage) => {
      const entry = zip.getEntry(safeFileName(stage.assetFileName));
      if (!entry) throw new Error(`Missing ${stage.assetFileName}.`);
      return entry.getData();
    });
    const reference = template.referenceFileName ? zip.getEntry(safeFileName(template.referenceFileName))?.getData() : undefined;
    return this.install(template, images, reference);
  }

  validate(template: CustomPetTemplate): void {
    safeIdentifier(template.id);
    if (template.schemaVersion !== 1) throw new Error("Unsupported template schema version.");
    if (!template.name.trim() || template.stages.length < 1 || template.stages.length > 8) {
      throw new Error("Template must have a name and one to eight stages.");
    }
    const indexes = new Set<number>();
    for (const stage of template.stages) {
      safeFileName(stage.assetFileName);
      if (indexes.has(stage.index)) throw new Error("Template stage indexes must be unique.");
      indexes.add(stage.index);
    }
    if (template.referenceFileName) safeFileName(template.referenceFileName);
  }

  private async validateImage(image: Buffer): Promise<void> {
    if (image.length < 32 || image.length > MAX_ENTRY_BYTES) throw new Error("Template image size is invalid.");
    let metadata: sharp.Metadata;
    try { metadata = await sharp(image, { failOn: "error" }).metadata(); } catch { throw new Error("Template contains a corrupt image."); }
    if (metadata.format !== "png" || !metadata.width || !metadata.height || metadata.width < 32 || metadata.height < 32 || metadata.width > 4_096 || metadata.height > 4_096) {
      throw new Error("Template images must be valid PNG files between 32 and 4096 pixels.");
    }
  }
}
