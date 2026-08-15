#!/usr/bin/env node

import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import sharp from "sharp";

const root = process.cwd();
const expansionRoot = path.join(root, "ArtSources", "Expansion200");
const plan = JSON.parse(fs.readFileSync(path.join(expansionRoot, "lineages.json"), "utf8"));
const outputRoot = path.join(expansionRoot, "ReviewSheets");
const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];
const perSheet = 5;

function escapeXML(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

function labelSVG(width, height, lines, size = 24) {
  const spans = lines.map((line, index) => `<text x="18" y="${28 + index * (size + 7)}" fill="${index === 0 ? "#F5F7FF" : "#8CEBDF"}" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="${index === 0 ? size : Math.max(13, size - 7)}" font-weight="${index === 0 ? 700 : 500}">${escapeXML(line)}</text>`).join("");
  return Buffer.from(`<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#11172B"/>${spans}</svg>`);
}

await fsp.mkdir(outputRoot, { recursive: true });
for (let offset = 0; offset < plan.themes.length; offset += perSheet) {
  const themes = plan.themes.slice(offset, offset + perSheet);
  const sheetIndex = String(offset / perSheet + 1).padStart(2, "0");

  const lineupWidth = 1200;
  const lineupImageHeight = 590;
  const lineupLabelHeight = 64;
  const lineupCanvas = sharp({ create: { width: lineupWidth, height: themes.length * (lineupImageHeight + lineupLabelHeight), channels: 3, background: "#080B18" } });
  const lineupLayers = [];
  for (let row = 0; row < themes.length; row += 1) {
    const theme = themes[row];
    const top = row * (lineupImageHeight + lineupLabelHeight);
    lineupLayers.push({ input: labelSVG(lineupWidth, lineupLabelHeight, [`${offset + row + 1}. ${theme.displayName}`, `${theme.tags.join(" · ")}  |  ${theme.id}`], 23), left: 0, top });
    const image = await sharp(path.join(expansionRoot, "Lineups", `${theme.id}.png`)).resize({ width: lineupWidth, height: lineupImageHeight, fit: "contain", background: "#00FF00" }).jpeg({ quality: 90, chromaSubsampling: "4:4:4" }).toBuffer();
    lineupLayers.push({ input: image, left: 0, top: top + lineupLabelHeight });
  }
  await lineupCanvas.composite(lineupLayers).jpeg({ quality: 88, chromaSubsampling: "4:4:4" }).toFile(path.join(outputRoot, `lineups-${sheetIndex}.jpg`));

  const assetWidth = 1200;
  const assetRowHeight = 272;
  const assetCanvas = sharp({ create: { width: assetWidth, height: themes.length * assetRowHeight, channels: 3, background: "#080B18" } });
  const assetLayers = [];
  for (let row = 0; row < themes.length; row += 1) {
    const theme = themes[row];
    const top = row * assetRowHeight;
    assetLayers.push({ input: labelSVG(assetWidth, 46, [`${offset + row + 1}. ${theme.displayName}`], 21), left: 0, top });
    for (let column = 0; column < stages.length; column += 1) {
      const left = 25 + column * 235;
      const stageLabel = labelSVG(220, 28, [stages[column].toUpperCase()], 14);
      assetLayers.push({ input: stageLabel, left, top: top + 45 });
      const image = await sharp(path.join(expansionRoot, "Resources", `${theme.id}-${stages[column]}.png`)).resize({ width: 220, height: 190, fit: "contain" }).png().toBuffer();
      assetLayers.push({ input: image, left, top: top + 76 });
    }
  }
  await assetCanvas.composite(assetLayers).jpeg({ quality: 91, chromaSubsampling: "4:4:4" }).toFile(path.join(outputRoot, `assets-${sheetIndex}.jpg`));
}

console.log(`Generated ${Math.ceil(plan.themes.length / perSheet) * 2} expansion review sheets.`);
