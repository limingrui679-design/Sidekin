#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const expansionRoot = path.join(root, "ArtSources", "Expansion200");
const plan = JSON.parse(fs.readFileSync(path.join(expansionRoot, "lineages.json"), "utf8"));
const progressPath = path.join(expansionRoot, "progress.json");
const progress = JSON.parse(fs.readFileSync(progressPath, "utf8"));
const [mode, ...arguments_] = process.argv.slice(2);
const ids = new Set(plan.themes.map((theme) => theme.id));

function writeProgress() {
  const temporaryPath = `${progressPath}.tmp`;
  fs.writeFileSync(temporaryPath, `${JSON.stringify(progress, null, 2)}\n`);
  fs.renameSync(temporaryPath, progressPath);
}

if (mode === "next") {
  const limit = Number(arguments_[0] ?? 4);
  const items = plan.themes
    .filter((theme) => !progress.generatedLineups.includes(theme.id))
    .slice(0, limit)
    .map((theme) => ({
      id: theme.id,
      prompt: fs.readFileSync(path.join(expansionRoot, "Prompts", `${theme.id}.txt`), "utf8")
    }));
  process.stdout.write(JSON.stringify(items));
} else if (["generated", "processed", "reviewed"].includes(mode)) {
  const key = `${mode}Lineages`.replace("generatedLineages", "generatedLineups");
  for (const id of arguments_) {
    if (!ids.has(id)) throw new Error(`Unknown expansion lineage: ${id}`);
    if (!progress[key].includes(id)) progress[key].push(id);
  }
  if (mode === "processed" && arguments_.some((id) => !progress.generatedLineups.includes(id))) {
    throw new Error("A lineage must be generated before it can be marked processed.");
  }
  if (mode === "reviewed" && arguments_.some((id) => !progress.processedLineages.includes(id))) {
    throw new Error("A lineage must be processed before it can be marked reviewed.");
  }
  writeProgress();
  console.log(`${mode}: ${arguments_.join(", ")}`);
} else if (mode === "summary") {
  console.log(JSON.stringify({
    generated: progress.generatedLineups.length,
    processed: progress.processedLineages.length,
    reviewed: progress.reviewedLineages.length,
    remaining: plan.themes.length - progress.generatedLineups.length
  }));
} else {
  console.error("Usage: node Scripts/expansion-progress.mjs next [limit] | generated|processed|reviewed id... | summary");
  process.exit(2);
}
