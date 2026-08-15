#!/usr/bin/env node

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import sharp from "sharp";

const root = process.cwd();
const expansionRoot = path.join(root, "ArtSources", "Expansion200");
const expansion = JSON.parse(fs.readFileSync(path.join(expansionRoot, "lineages.json"), "utf8"));
const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];
const localCuratedRoot = path.join(expansionRoot, "Resources");
const localProcessedRoot = path.join(expansionRoot, "Processed");
const integratedRoot = path.join(root, "Sources", "SidekinApp", "Resources", "Characters");
const curatedRoot = fs.existsSync(localCuratedRoot) ? localCuratedRoot : integratedRoot;

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

requireCondition(expansion.themes.length === 100, `Expected 100 expansion lineages, found ${expansion.themes.length}.`);
const expectedNames = expansion.themes.flatMap((theme) => stages.map((stage) => `${theme.id}-${stage}.png`));
requireCondition(expectedNames.length === 500 && new Set(expectedNames).size === 500, "Expansion asset names are incomplete or duplicated.");

const curatedNames = fs.readdirSync(curatedRoot).filter((name) => name.endsWith(".png")).sort();
requireCondition(curatedNames.length === 500, `Expected exactly 500 curated expansion PNGs, found ${curatedNames.length}.`);
requireCondition(curatedNames.join("\n") === expectedNames.slice().sort().join("\n"), "Curated expansion asset names drifted from the lineage plan.");

const binaryHashes = new Set();
for (const theme of expansion.themes) {
  for (const stage of stages) {
    const name = `${theme.id}-${stage}.png`;
    const curatedPath = path.join(curatedRoot, name);
    const processedPath = path.join(localProcessedRoot, theme.id, `${stage}-source.png`);
    const integratedPath = path.join(integratedRoot, name);
    const requiredCopies = [curatedPath, integratedPath];
    if (fs.existsSync(localProcessedRoot)) requiredCopies.push(processedPath);
    for (const candidate of requiredCopies) {
      requireCondition(fs.existsSync(candidate), `Missing expansion asset copy: ${path.relative(root, candidate)}.`);
    }

    const curatedData = fs.readFileSync(curatedPath);
    const digest = createHash("sha256").update(curatedData).digest("hex");
    requireCondition(!binaryHashes.has(digest), `Duplicate final expansion image detected at ${name}.`);
    binaryHashes.add(digest);
    const integratedDigest = createHash("sha256").update(fs.readFileSync(integratedPath)).digest("hex");
    requireCondition(integratedDigest === digest, `${path.relative(root, integratedPath)} does not match the curated final asset.`);

    const image = sharp(curatedData).ensureAlpha();
    const metadata = await image.metadata();
    requireCondition(metadata.width === 1254 && metadata.height === 1254 && metadata.hasAlpha, `${name} is not a 1254×1254 alpha PNG.`);
    const { data, info } = await image.raw().toBuffer({ resolveWithObject: true });
    requireCondition(info.channels === 4, `${name} did not decode to RGBA.`);

    let occupied = 0;
    for (let pixel = 0; pixel < info.width * info.height; pixel += 1) {
      if (data[pixel * 4 + 3] > 18) occupied += 1;
    }
    const occupancy = occupied / (info.width * info.height);
    requireCondition(occupancy > 0.045 && occupancy < 0.72, `${name} has suspicious visible occupancy ${occupancy.toFixed(4)}.`);

    const cornerOffsets = [
      3,
      (info.width - 1) * 4 + 3,
      (info.height - 1) * info.width * 4 + 3,
      ((info.height * info.width) - 1) * 4 + 3
    ];
    requireCondition(cornerOffsets.every((offset) => data[offset] <= 18), `${name} has a non-transparent corner.`);
  }
}

console.log("Verified 500 unique expansion PNGs, every source crop, exact integrated copies, dimensions, alpha occupancy, and transparent corners.");
