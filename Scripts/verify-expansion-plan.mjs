#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import sharp from "sharp";
import { isDeepStrictEqual } from "node:util";

const root = process.cwd();
const expansionRoot = path.join(root, "ArtSources", "Expansion200");
const expansion = JSON.parse(fs.readFileSync(path.join(expansionRoot, "lineages.json"), "utf8"));
const catalog = JSON.parse(fs.readFileSync(path.join(root, "ArtSources", "PET_THEME_CATALOG.json"), "utf8"));
const posterMap = JSON.parse(fs.readFileSync(path.join(expansionRoot, "POSTER_CANON_MAP.json"), "utf8"));
const progress = JSON.parse(fs.readFileSync(path.join(expansionRoot, "progress.json"), "utf8"));
const requireFullAssets = process.argv.includes("--full");

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

requireCondition(expansion.themes.length === 100, `Expected 100 expansion lineages, found ${expansion.themes.length}.`);
requireCondition(catalog.themes.length === 200, `Expected 200 integrated lineages, found ${catalog.themes.length}.`);
requireCondition(catalog.schemaVersion === 2, `Expected tag catalog schema 2, found ${catalog.schemaVersion}.`);
const combined = catalog.themes;

for (const theme of combined) {
  requireCondition(!Object.hasOwn(theme, "category"), `${theme.id} reintroduces a fixed category.`);
  requireCondition(Array.isArray(theme.tags) && theme.tags.length >= 3, `${theme.id} needs at least three free-form tags.`);
  requireCondition(typeof theme.artStyle === "string" && theme.artStyle.trim().length > 0, `${theme.id} needs an explicit art style.`);
}

for (const key of ["id", "displayName", "lineageIntroduction", "existenceAnchor", "silhouetteAnchor", "motionAnchor", "materialAnchor", "energyAnchor"]) {
  requireCondition(new Set(combined.map((theme) => theme[key])).size === combined.length, `Combined catalog contains a duplicate ${key}.`);
}

const catalogByID = new Map(catalog.themes.map((theme) => [theme.id, theme]));
for (const theme of expansion.themes) {
  requireCondition(catalogByID.has(theme.id), `Integrated catalog is missing expansion lineage ${theme.id}.`);
  requireCondition(isDeepStrictEqual(catalogByID.get(theme.id), theme), `Integrated catalog drifted from expansion source for ${theme.id}.`);
}

const stages = ["egg", "hatchling", "juvenile", "ascended", "legendary"];
for (const theme of expansion.themes) {
  requireCondition(!Object.hasOwn(theme, "category"), `${theme.id} reintroduces a fixed category.`);
  requireCondition(Array.isArray(theme.tags) && theme.tags.length >= 3, `${theme.id} needs searchable free-form tags.`);
  requireCondition(theme.forms.map((form) => form.stage).join(",") === stages.join(","), `${theme.id} does not have five canonical stages.`);
  const forbiddenTags = new Set(["architecture", "building", "flora", "fungi", "landscape", "plant"]);
  requireCondition(theme.tags.every((tag) => !forbiddenTags.has(tag)), `${theme.id} adds a forbidden architecture or nature theme.`);
  requireCondition(fs.existsSync(path.join(expansionRoot, "Prompts", `${theme.id}.txt`)), `Missing lineup prompt for ${theme.id}.`);
}

const knownIDs = new Set(combined.map((theme) => theme.id));
const mappedIDs = new Set();
for (const poster of posterMap.posters) {
  requireCondition(fs.existsSync(path.join(root, poster.file)), `Poster map references missing file ${poster.file}.`);
  requireCondition(poster.subjects.length >= 8, `${poster.file} maps too few readable subjects.`);
  for (const [label, themeID] of poster.subjects) {
    requireCondition(label.length >= 4, `${poster.file} contains a weak subject label.`);
    requireCondition(knownIDs.has(themeID), `${poster.file} maps ${label} to unknown lineage ${themeID}.`);
    mappedIDs.add(themeID);
  }
}

for (const key of ["generatedLineups", "processedLineages", "reviewedLineages"]) {
  requireCondition(new Set(progress[key]).size === progress[key].length, `Duplicate entries in progress.${key}.`);
  requireCondition(progress[key].every((id) => expansion.themes.some((theme) => theme.id === id)), `Unknown lineage in progress.${key}.`);
}
requireCondition(progress.processedLineages.every((id) => progress.generatedLineups.includes(id)), "Processed lineage is missing its generated-lineup checkpoint.");
requireCondition(progress.reviewedLineages.every((id) => progress.processedLineages.includes(id)), "Reviewed lineage is missing its processed checkpoint.");

if (requireFullAssets) {
  requireCondition(progress.generatedLineups.length === 100, "Full verification requires 100 generated lineups.");
  requireCondition(progress.processedLineages.length === 100, "Full verification requires 100 processed lineages.");
  requireCondition(progress.reviewedLineages.length === 100, "Full verification requires 100 reviewed lineages.");
  const expected = new Set(expansion.themes.flatMap((theme) => stages.map((stage) => `${theme.id}-${stage}.png`)));
  const expansionResources = path.join(expansionRoot, "Resources");
  const integratedResources = path.join(root, "Sources", "SidekinApp", "Resources", "Characters");
  const resourceDirectory = fs.existsSync(expansionResources) ? expansionResources : integratedResources;
  const resources = fs.readdirSync(resourceDirectory).filter((name) => expected.has(name));
  requireCondition(resources.length === 500, `Full verification requires 500 integrated expansion assets, found ${resources.length}.`);
  for (const name of resources) {
    const imagePath = path.join(resourceDirectory, name);
    const metadata = await sharp(imagePath).metadata();
    requireCondition(metadata.width === 1254 && metadata.height === 1254 && metadata.hasAlpha, `${name} is not a 1254-square alpha PNG.`);
  }
  const reviewSheets = fs.readdirSync(path.join(expansionRoot, "ReviewSheets"))
    .filter((name) => /^assets-[0-9]{2}\.jpg$/.test(name));
  requireCondition(reviewSheets.length === 20, `Full verification requires 20 expansion asset review sheets, found ${reviewSheets.length}.`);
}

console.log(`Verified integrated tag-based expansion: 100 new lineages, 500 described forms, ${mappedIDs.size} poster-canon lineages, ${progress.reviewedLineages.length}/100 reviewed.`);
