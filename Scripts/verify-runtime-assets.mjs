import { createHash } from "node:crypto";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const assets = path.join(root, "RuntimeAssets");
const characters = path.join(assets, "Characters");
const thumbnails = path.join(assets, "Thumbnails");
const manifest = JSON.parse(await readFile(path.join(assets, "manifest.json"), "utf8"));
const catalog = JSON.parse(await readFile(path.join(root, "ArtSources", "PET_THEME_CATALOG.json"), "utf8"));
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

if (manifest.schemaVersion !== 1 || manifest.lineageCount !== 200 || manifest.formCount !== 1_000) throw new Error("Runtime asset manifest count or schema is invalid.");
if (catalog.schemaVersion !== 2 || catalog.themes.length !== manifest.lineageCount) throw new Error("Runtime assets do not match the current catalog.");
if (manifest.sourceArchive?.commit !== "0fca27df3ae9e4e32ab37651efb1a8f756912ffb") throw new Error("Runtime assets lack an immutable full-PNG source reference.");

const characterFiles = (await readdir(characters)).filter((file) => file.endsWith(".webp")).sort();
const thumbnailFiles = (await readdir(thumbnails)).filter((file) => file.endsWith(".webp")).sort();
if (characterFiles.length !== 1_000 || thumbnailFiles.length !== 200) throw new Error("Runtime asset directory counts are invalid.");
if ((await readdir(characters)).some((file) => file.endsWith(".png"))) throw new Error("Runtime characters must not include full-size PNG files.");

const expectedCharacters = catalog.themes.flatMap((theme) => manifest.stages.map((stage) => `${theme.id}-${stage}.webp`)).sort();
const expectedThumbnails = catalog.themes.map((theme) => `${theme.id}-legendary.webp`).sort();
if (expectedCharacters.some((file, index) => file !== characterFiles[index])) throw new Error("Runtime character filenames do not cover the full catalog.");
if (expectedThumbnails.some((file, index) => file !== thumbnailFiles[index])) throw new Error("Runtime thumbnail filenames do not cover the full catalog.");

const records = new Map(manifest.forms.map((record) => [record.runtimeFile, record]));
let runtimeBytes = 0;
let thumbnailBytes = 0;
let next = 0;
async function worker() {
  while (true) {
    const index = next++;
    if (index >= characterFiles.length) return;
    const file = characterFiles[index];
    const data = await readFile(path.join(characters, file));
    const record = records.get(file);
    if (!record || record.runtimeBytes !== data.length || record.runtimeSHA256 !== sha256(data)) throw new Error(`Runtime manifest mismatch: ${file}`);
    const metadata = await sharp(data, { failOn: "error" }).metadata();
    if (metadata.format !== "webp" || metadata.width !== 768 || metadata.height !== 768 || !metadata.hasAlpha) throw new Error(`Invalid runtime WebP: ${file}`);
    runtimeBytes += data.length;
    if (record.thumbnailFile) {
      const thumbnail = await readFile(path.join(thumbnails, record.thumbnailFile));
      if (record.thumbnailBytes !== thumbnail.length || record.thumbnailSHA256 !== sha256(thumbnail)) throw new Error(`Thumbnail manifest mismatch: ${record.thumbnailFile}`);
      const preview = await sharp(thumbnail, { failOn: "error" }).metadata();
      if (preview.format !== "webp" || preview.width !== 320 || preview.height !== 320 || !preview.hasAlpha) throw new Error(`Invalid thumbnail WebP: ${record.thumbnailFile}`);
      thumbnailBytes += thumbnail.length;
    }
  }
}
await Promise.all(Array.from({ length: 8 }, () => worker()));

if (runtimeBytes !== manifest.totals.runtimeBytes || thumbnailBytes !== manifest.totals.thumbnailBytes) throw new Error("Runtime asset byte totals do not match the manifest.");
if (runtimeBytes > 120 * 1_048_576 || thumbnailBytes > 10 * 1_048_576) throw new Error("Runtime asset budget exceeded.");
const manifestBytes = (await stat(path.join(assets, "manifest.json"))).size;
console.log(`Verified 1,000 transparent runtime WebPs (${(runtimeBytes / 1_048_576).toFixed(1)} MiB), 200 lazy thumbnails (${(thumbnailBytes / 1_048_576).toFixed(1)} MiB), and immutable PNG provenance (${(manifestBytes / 1_024).toFixed(1)} KiB manifest).`);
