import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const sourceDirectory = process.env.SIDEKIN_SOURCE_CORPUS
  ? path.resolve(process.env.SIDEKIN_SOURCE_CORPUS)
  : path.join(root, "Sources", "SidekinApp", "Resources", "Characters");
const outputRoot = path.join(root, "RuntimeAssets");
const characterDirectory = path.join(outputRoot, "Characters");
const thumbnailDirectory = path.join(outputRoot, "Thumbnails");
const catalogPath = path.join(root, "ArtSources", "PET_THEME_CATALOG.json");
const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];
const runtimeSize = 768;
const thumbnailSize = 320;
const concurrency = Math.max(2, Math.min(8, Number(process.env.SIDEKIN_ASSET_CONCURRENCY) || 6));

if (!existsSync(sourceDirectory)) {
  throw new Error("The full PNG corpus is not checked out. Set SIDEKIN_SOURCE_CORPUS to the Characters directory from archive/full-png-corpus-v2.1.");
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const catalog = JSON.parse(await readFile(catalogPath, "utf8"));
if (catalog.schemaVersion !== 2 || catalog.themes.length !== 200) throw new Error("Expected the audited schema-2, 200-lineage catalog.");

const expected = catalog.themes.flatMap((theme) => stages.map((stage) => `${theme.id}-${stage}.png`));
const actual = (await readdir(sourceDirectory)).filter((file) => file.endsWith(".png")).sort();
if (actual.length !== expected.length || expected.some((file) => !actual.includes(file))) {
  throw new Error(`Expected ${expected.length} complete source PNGs, found ${actual.length}.`);
}

await rm(outputRoot, { recursive: true, force: true });
await Promise.all([
  mkdir(characterDirectory, { recursive: true }),
  mkdir(thumbnailDirectory, { recursive: true })
]);

const records = Array.from({ length: expected.length });
let nextIndex = 0;
let completed = 0;

async function worker() {
  while (true) {
    const index = nextIndex++;
    if (index >= expected.length) return;
    const sourceFile = expected[index];
    const sourcePath = path.join(sourceDirectory, sourceFile);
    const source = await readFile(sourcePath);
    const metadata = await sharp(source, { failOn: "error" }).metadata();
    if (metadata.format !== "png" || metadata.width !== 1_254 || metadata.height !== 1_254 || !metadata.hasAlpha) {
      throw new Error(`${sourceFile} is not an audited 1254x1254 transparent PNG.`);
    }

    const runtimeFile = sourceFile.replace(/\.png$/, ".webp");
    const runtime = await sharp(source)
      .resize(runtimeSize, runtimeSize, { fit: "contain", withoutEnlargement: true })
      .webp({ quality: 88, alphaQuality: 100, smartSubsample: true, effort: 4 })
      .toBuffer();
    await writeFile(path.join(characterDirectory, runtimeFile), runtime);

    let thumbnailFile = null;
    let thumbnailBytes = null;
    let thumbnailSHA256 = null;
    if (sourceFile.endsWith("-legendary.png")) {
      thumbnailFile = runtimeFile;
      const thumbnail = await sharp(source)
        .resize(thumbnailSize, thumbnailSize, { fit: "contain", withoutEnlargement: true })
        .webp({ quality: 82, alphaQuality: 100, smartSubsample: true, effort: 4 })
        .toBuffer();
      await writeFile(path.join(thumbnailDirectory, thumbnailFile), thumbnail);
      thumbnailBytes = thumbnail.length;
      thumbnailSHA256 = sha256(thumbnail);
    }

    records[index] = {
      sourceFile,
      sourceBytes: source.length,
      sourceSHA256: sha256(source),
      runtimeFile,
      runtimeBytes: runtime.length,
      runtimeSHA256: sha256(runtime),
      thumbnailFile,
      thumbnailBytes,
      thumbnailSHA256
    };
    completed += 1;
    if (completed % 100 === 0 || completed === expected.length) process.stdout.write(`Converted ${completed}/${expected.length}\n`);
  }
}

await Promise.all(Array.from({ length: concurrency }, () => worker()));

const runtimeBytes = records.reduce((sum, record) => sum + record.runtimeBytes, 0);
const thumbnailBytes = records.reduce((sum, record) => sum + (record.thumbnailBytes ?? 0), 0);
const sourceBytes = records.reduce((sum, record) => sum + record.sourceBytes, 0);
const manifest = {
  schemaVersion: 1,
  catalogSchemaVersion: catalog.schemaVersion,
  sourceArchive: {
    repository: "limingrui679-design/Sidekin",
    branch: "archive/full-png-corpus-v2.1",
    commit: "0fca27df3ae9e4e32ab37651efb1a8f756912ffb"
  },
  lineageCount: catalog.themes.length,
  formCount: records.length,
  stages,
  encoding: {
    runtime: { format: "webp", width: runtimeSize, height: runtimeSize, quality: 88, alphaQuality: 100 },
    thumbnail: { format: "webp", width: thumbnailSize, height: thumbnailSize, quality: 82, alphaQuality: 100 }
  },
  totals: { sourceBytes, runtimeBytes, thumbnailBytes },
  forms: records
};
await writeFile(path.join(outputRoot, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);

const outputSize = (await stat(path.join(outputRoot, "manifest.json"))).size;
console.log(`Built ${records.length} runtime WebPs and ${catalog.themes.length} thumbnails. Runtime ${(runtimeBytes / 1_048_576).toFixed(1)} MiB; thumbnails ${(thumbnailBytes / 1_048_576).toFixed(1)} MiB; manifest ${(outputSize / 1_024).toFixed(1)} KiB.`);
