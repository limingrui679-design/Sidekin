#!/usr/bin/env node

import { lstat, readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const projectRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const targets = [
  ".gitattributes",
  ".github",
  ".gitignore",
  "README.md",
  "LICENSE",
  "SECURITY.md",
  "Package.swift",
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "Sources",
  "src",
  "tests",
  "Scripts",
  "Support",
  "ArtSources",
  "docs"
];

const ignoredDirectories = new Set([".git", ".build", ".swiftpm", "artifacts", "dist", "node_modules", "out"]);
const ignoredExtensions = new Set([".gif", ".icns", ".ico", ".jpeg", ".jpg", ".png", ".webp", ".zip"]);
const legacyBrandPattern = /CainiaoPet|Cainiao Pet|cainiaopet|cainiao/;
const legacyBrandAllowlist = new Set([
  "Sources/SidekinCore/PetPersistence.swift",
  "Sources/SidekinCore/CodexIntegration.swift",
  "Sources/SidekinCreator/APIKeyStore.swift",
  "Sources/SidekinApp/Views/ControlCenterView.swift",
  "Sources/SidekinSelfTest/main.swift",
  "src/main/paths.ts",
  "src/shared/codex.ts",
  "Scripts/verify-english-text.mjs"
]);
const cjkPattern = /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u{20000}-\u{2FA1F}\u3040-\u309F\u30A0-\u30FF\uAC00-\uD7AF]/u;

async function collectFiles(candidate, files) {
  const metadata = await lstat(candidate);
  if (metadata.isSymbolicLink()) return;
  if (metadata.isDirectory()) {
    if (ignoredDirectories.has(path.basename(candidate))) return;
    const entries = await readdir(candidate);
    entries.sort();
    for (const entry of entries) await collectFiles(path.join(candidate, entry), files);
    return;
  }
  if (metadata.isFile() && !ignoredExtensions.has(path.extname(candidate).toLowerCase())) files.push(candidate);
}

const files = [];
for (const target of targets) await collectFiles(path.join(projectRoot, target), files);

const cjkHits = [];
const unexpectedLegacyHits = [];
for (const file of files) {
  const relativePath = path.relative(projectRoot, file).split(path.sep).join("/");
  const content = await readFile(file, "utf8");
  if (cjkPattern.test(content)) {
    const lines = content.split(/\r?\n/u);
    for (let index = 0; index < lines.length; index += 1) {
      if (cjkPattern.test(lines[index])) cjkHits.push(`${relativePath}:${index + 1}`);
    }
  }
  if (legacyBrandPattern.test(content) && !legacyBrandAllowlist.has(relativePath)) unexpectedLegacyHits.push(relativePath);
}

if (cjkHits.length > 0) {
  console.error("English-text verification failed: CJK text remains in project-facing files:");
  console.error(cjkHits.join("\n"));
  process.exit(1);
}
if (unexpectedLegacyHits.length > 0) {
  console.error("Brand verification failed: the retired name remains outside migration code:");
  console.error(unexpectedLegacyHits.join("\n"));
  process.exit(1);
}

console.log(`Verified ${files.length} English-only project text files and Sidekin branding; retired-name references are migration-only.`);
