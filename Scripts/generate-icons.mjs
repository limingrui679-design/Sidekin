import sharp from "sharp";
import pngToIco from "png-to-ico";
import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const source = path.join(root, "docs/readme/app-icon.png");
const assets = path.join(root, "assets");
await mkdir(assets, { recursive: true });
await sharp(source).resize(1_024, 1_024).png().toFile(path.join(assets, "app-icon.png"));
const icoPNGs = [];
for (const size of [16, 24, 32, 48, 64, 128, 256]) {
  icoPNGs.push(await sharp(source).resize(size, size).png().toBuffer());
}
await writeFile(path.join(assets, "app-icon.ico"), await pngToIco(icoPNGs));
await sharp(source).resize(36, 36).grayscale().threshold(100).png().toFile(path.join(assets, "tray-template.png"));

if (process.platform === "darwin") {
  const iconset = path.join(assets, "app-icon.iconset");
  await rm(iconset, { recursive: true, force: true });
  await mkdir(iconset, { recursive: true });
  for (const size of [16, 32, 128, 256, 512]) {
    await sharp(source).resize(size, size).png().toFile(path.join(iconset, `icon_${size}x${size}.png`));
    await sharp(source).resize(size * 2, size * 2).png().toFile(path.join(iconset, `icon_${size}x${size}@2x.png`));
  }
  await promisify(execFile)("iconutil", ["-c", "icns", iconset, "-o", path.join(assets, "app-icon.icns")]);
  await rm(iconset, { recursive: true, force: true });
}
console.log("Generated cross-platform app and tray icons.");
