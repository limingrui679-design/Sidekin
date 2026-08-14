import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const captures = path.join(root, "artifacts", "previews");
const output = path.join(root, "docs", "readme");
const controlPath = path.join(captures, "command-center.png");
const floatingPath = path.join(captures, "floating-pet.png");
const workshopPath = path.join(captures, "workshop.png");

for (const file of [controlPath, floatingPath, workshopPath]) {
  if (!existsSync(file)) throw new Error(`Missing runtime capture: ${file}. Run npm run capture first.`);
}
await mkdir(output, { recursive: true });

async function rounded(input, width, radius) {
  const resized = await sharp(input).resize({ width }).png().toBuffer();
  const metadata = await sharp(resized).metadata();
  const mask = Buffer.from(`<svg width="${metadata.width}" height="${metadata.height}"><rect width="100%" height="100%" rx="${radius}" fill="white"/></svg>`);
  return sharp(resized).composite([{ input: mask, blend: "dest-in" }]).png().toBuffer();
}

const control = await rounded(controlPath, 1_500, 34);
const controlMetadata = await sharp(control).metadata();
const floating = await sharp(floatingPath).resize({ width: 650 }).png().toBuffer();
const floatingMetadata = await sharp(floating).metadata();
const backdrop = Buffer.from(`
  <svg width="2400" height="1350" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#221452"/><stop offset=".48" stop-color="#0b2941"/><stop offset="1" stop-color="#050815"/></linearGradient>
      <radialGradient id="glow"><stop stop-color="#54eee3" stop-opacity=".28"/><stop offset="1" stop-color="#54eee3" stop-opacity="0"/></radialGradient>
      <filter id="shadow"><feGaussianBlur stdDeviation="28"/></filter>
    </defs>
    <rect width="2400" height="1350" fill="url(#bg)"/>
    <circle cx="1810" cy="670" r="600" fill="url(#glow)"/>
    <text x="78" y="105" fill="#59eee5" font-family="SFMono-Regular,Consolas,monospace" font-size="34" font-weight="700" letter-spacing="8">LIVE CODEX COMPANION</text>
    <text x="78" y="172" fill="white" font-family="Arial,sans-serif" font-size="52" font-weight="800">Tasks become motion, mood, and growth.</text>
    <rect x="48" y="198" width="1560" height="1040" rx="46" fill="#000" opacity=".52" filter="url(#shadow)"/>
    <rect x="1645" y="198" width="705" height="1085" rx="80" fill="#0b0e25" opacity=".72" stroke="#6df4e9" stroke-opacity=".24" stroke-width="3"/>
    <text x="1720" y="1250" fill="#aab1c9" font-family="SFMono-Regular,Consolas,monospace" font-size="25" font-weight="700" letter-spacing="4">FLOATING VIEW</text>
  </svg>`);

await sharp(backdrop)
  .composite([
    { input: control, left: 78, top: 220 },
    { input: floating, left: 1_675 + Math.max(0, Math.floor((650 - (floatingMetadata.width ?? 650)) / 2)), top: 215 }
  ])
  .jpeg({ quality: 90, chromaSubsampling: "4:4:4" })
  .toFile(path.join(output, "live-desktop.jpg"));

await sharp(workshopPath)
  .resize({ width: 2_000 })
  .jpeg({ quality: 88, chromaSubsampling: "4:4:4" })
  .toFile(path.join(output, "workshop.jpg"));

if (!controlMetadata.width || !floatingMetadata.width) throw new Error("Runtime preview images are invalid.");
console.log("Generated README runtime previews from the isolated local capture.");
