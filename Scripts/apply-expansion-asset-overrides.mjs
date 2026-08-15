#!/usr/bin/env node

import { createHash } from "node:crypto";
import fs from "node:fs";
import { readFile, rename } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const expansionRoot = path.join(root, "ArtSources", "Expansion200");
const configuration = JSON.parse(
  fs.readFileSync(path.join(expansionRoot, "FINAL_ASSET_OVERRIDES.json"), "utf8")
);

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

async function applyOverride(target, override) {
  const original = await readFile(target);
  const originalHash = sha256(original);
  if (originalHash === override.outputSHA256) return "already normalized";
  if (originalHash !== override.sourceSHA256) {
    throw new Error(`${target} does not match the recorded source or normalized output hash.`);
  }

  const raw = await sharp(original).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const [firstColumn, lastColumn] = override.clearColumns;
  for (let y = 0; y < raw.info.height; y += 1) {
    for (let x = firstColumn; x <= lastColumn; x += 1) {
      raw.data[(y * raw.info.width + x) * 4 + 3] = 0;
    }
  }

  const cleaned = await sharp(raw.data, {
    raw: { width: raw.info.width, height: raw.info.height, channels: 4 }
  }).png().toBuffer();
  const trimmed = await sharp(cleaned)
    .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer({ resolveWithObject: true });
  const width = Math.round(trimmed.info.width * override.scale);
  const height = Math.round(trimmed.info.height * override.scale);
  const resized = await sharp(trimmed.data)
    .resize(width, height, { fit: "fill", kernel: sharp.kernel.lanczos3 })
    .png()
    .toBuffer();
  const temporary = `${target}.override.tmp.png`;
  await sharp({
    create: {
      width: 1_254,
      height: 1_254,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 }
    }
  })
    .composite([{
      input: resized,
      left: Math.floor((1_254 - width) / 2),
      top: Math.floor((1_254 - height) / 2)
    }])
    .png()
    .toFile(temporary);

  const normalized = await readFile(temporary);
  if (sha256(normalized) !== override.outputSHA256) {
    throw new Error(`${override.fileName} normalization output hash drifted.`);
  }
  await rename(temporary, target);
  return "normalized";
}

for (const override of configuration.overrides) {
  const targets = [
    path.join(expansionRoot, "Resources", override.fileName),
    path.join(root, "Sources", "SidekinApp", "Resources", "Characters", override.fileName)
  ];
  for (const target of targets) {
    if (!fs.existsSync(target)) throw new Error(`Missing override target: ${target}`);
    console.log(`${path.relative(root, target)}: ${await applyOverride(target, override)}`);
  }
}
