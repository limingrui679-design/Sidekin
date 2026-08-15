#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import sharp from "sharp";

const [, , inputPath, themeID, sourceDirectory, resourceDirectory, assetPrepPath] = process.argv;
const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];

if (!inputPath || !themeID || !sourceDirectory || !resourceDirectory || !assetPrepPath) {
  console.error("Usage: node Scripts/split-five-stage-lineup.mjs lineup.png theme-id source-dir resource-dir asset-prep-binary");
  process.exit(2);
}

const { data, info } = await sharp(inputPath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
const border = [];
for (let x = 0; x < info.width; x += Math.max(1, Math.floor(info.width / 256))) {
  border.push([x, 0], [x, info.height - 1]);
}
for (let y = 1; y < info.height - 1; y += Math.max(1, Math.floor(info.height / 128))) {
  border.push([0, y], [info.width - 1, y]);
}

const background = border.reduce((sum, [x, y]) => {
  const offset = (y * info.width + x) * 4;
  sum[0] += data[offset];
  sum[1] += data[offset + 1];
  sum[2] += data[offset + 2];
  return sum;
}, [0, 0, 0]).map((value) => value / border.length);

const occupancy = Array.from({ length: info.width }, () => 0);
for (let x = 0; x < info.width; x += 1) {
  for (let y = 0; y < info.height; y += 1) {
    const offset = (y * info.width + x) * 4;
    const distance = Math.hypot(
      data[offset] - background[0],
      data[offset + 1] - background[1],
      data[offset + 2] - background[2]
    );
    if (data[offset + 3] > 8 && distance > 62) occupancy[x] += 1;
  }
}

const smoothingRadius = Math.max(3, Math.round(info.width / 350));
const smoothed = occupancy.map((_, x) => {
  let total = 0;
  let count = 0;
  for (let candidate = Math.max(0, x - smoothingRadius); candidate <= Math.min(info.width - 1, x + smoothingRadius); candidate += 1) {
    total += occupancy[candidate];
    count += 1;
  }
  return total / count;
});

// Evolution forms intentionally grow toward the right, so the lowest-ink
// valleys are searched in progressively wider slots instead of assuming five
// equal boxes. This tolerates halos, tails, and detached energy shards.
const searchWindows = [
  [0.08, 0.25],
  [0.22, 0.45],
  [0.40, 0.66],
  [0.60, 0.90]
];
const boundaries = [0];
for (const [lower, upper] of searchWindows) {
  const minimumX = Math.max(boundaries.at(-1) + Math.round(info.width * 0.09), Math.round(info.width * lower));
  const maximumX = Math.round(info.width * upper);
  let bestX = minimumX;
  for (let x = minimumX + 1; x <= maximumX; x += 1) {
    if (smoothed[x] < smoothed[bestX]) bestX = x;
  }
  boundaries.push(bestX);
}
boundaries.push(info.width);

const minimumSlotWidth = Math.round(info.width * 0.09);
for (let index = 1; index < boundaries.length; index += 1) {
  if (boundaries[index] - boundaries[index - 1] < minimumSlotWidth) {
    throw new Error(`Could not isolate five stages; boundaries=${boundaries.join(",")}`);
  }
}

await fs.mkdir(sourceDirectory, { recursive: true });
await fs.mkdir(resourceDirectory, { recursive: true });
const prepArguments = [];
for (let index = 0; index < stages.length; index += 1) {
  const left = boundaries[index];
  const width = boundaries[index + 1] - left;
  const sourcePath = path.join(sourceDirectory, `${stages[index]}-source.png`);
  const outputPath = path.join(resourceDirectory, `${themeID}-${stages[index]}.png`);
  await sharp(inputPath).extract({ left, top: 0, width, height: info.height }).png().toFile(sourcePath);
  prepArguments.push(sourcePath, outputPath);
}

execFileSync(assetPrepPath, prepArguments, { stdio: "inherit" });
console.log(`Split ${themeID} at ${boundaries.join(",")} into five normalized assets.`);
