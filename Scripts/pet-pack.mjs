#!/usr/bin/env node
import AdmZip from "adm-zip";
import { createHash, randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const FORMAT = "sidekin.pet-pack";
const SCHEMA = 2;
const MAX_PACK_BYTES = 96 * 1024 * 1024;
const MAX_FILE_BYTES = 20 * 1024 * 1024;
const MAX_MANIFEST_BYTES = 1024 * 1024;
const MIN_SIDEKIN_VERSION = "2.2.0";
const PROFILES = new Set(["agile", "bouncing", "buoyant", "flowing", "gliding", "heavy", "marching", "mechanical", "orbiting", "poised", "prowling", "pulsing", "rolling", "rooted", "serpentine", "skittering", "spectral", "swarming", "swimming", "winged"]);

function fail(message) { throw new Error(message); }
function safeName(value) {
  if (typeof value !== "string" || path.basename(value) !== value || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(value)) fail(`Unsafe file name: ${String(value)}`);
  return value;
}
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function versionParts(value) { return value.split(".").map(Number); }
function newerThanSupported(value) {
  const candidate = versionParts(value);
  const supported = versionParts(MIN_SIDEKIN_VERSION);
  for (let index = 0; index < 3; index += 1) {
    if (candidate[index] !== supported[index]) return candidate[index] > supported[index];
  }
  return false;
}

function validateManifest(manifest) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) fail("template.json must contain one JSON object.");
  if (manifest.schemaVersion !== SCHEMA || manifest.packFormat !== FORMAT) fail(`Expected ${FORMAT} schema ${SCHEMA}.`);
  safeName(manifest.id);
  if (typeof manifest.name !== "string" || !manifest.name.trim() || manifest.name.length > 60) fail("name must contain 1–60 characters.");
  if (typeof manifest.author !== "string" || !manifest.author.trim() || manifest.author.length > 120) fail("author is required and must be at most 120 characters.");
  if (typeof manifest.license !== "string" || !manifest.license.trim() || manifest.license.length > 160) fail("license is required and must be at most 160 characters.");
  if (typeof manifest.basePrompt !== "string" || !manifest.basePrompt.trim() || manifest.basePrompt.length > 2_000) fail("basePrompt is required and must be at most 2,000 characters.");
  if (typeof manifest.artDirection !== "string" || !manifest.artDirection.trim() || manifest.artDirection.length > 1_000) fail("artDirection is required and must be at most 1,000 characters.");
  if (!["text", "restyle", "faithful"].includes(manifest.generationMode)) fail("generationMode must be text, restyle, or faithful.");
  if (manifest.generationQuality && !["low", "medium", "high"].includes(manifest.generationQuality)) fail("generationQuality must be low, medium, or high.");
  if (typeof manifest.createdAt !== "string" || !Number.isFinite(new Date(manifest.createdAt).getTime())) fail("createdAt must be a valid date.");
  safeName(manifest.fallbackTheme);
  if (!PROFILES.has(manifest.motionProfile)) fail(`Unsupported motionProfile. Choose one of: ${[...PROFILES].join(", ")}.`);
  if (!/^\d+\.\d+\.\d+$/.test(manifest.minSidekinVersion ?? "")) fail("minSidekinVersion must use x.y.z format.");
  if (newerThanSupported(manifest.minSidekinVersion)) fail(`This pack requires Sidekin ${manifest.minSidekinVersion} or newer.`);
  if (!Array.isArray(manifest.stages) || manifest.stages.length < 1 || manifest.stages.length > 8) fail("stages must contain 1–8 entries.");
  let threshold = -1;
  const files = new Set();
  manifest.stages.forEach((stage, index) => {
    if (!stage || stage.index !== index) fail("Stage indexes must be contiguous and start at zero.");
    safeName(stage.id);
    safeName(stage.assetFileName);
    if (!stage.assetFileName.toLowerCase().endsWith(".png")) fail("Stage assets must be PNG files.");
    if (files.has(stage.assetFileName.toLowerCase())) fail("Stage asset file names must be unique.");
    files.add(stage.assetFileName.toLowerCase());
    if (typeof stage.name !== "string" || !stage.name.trim() || stage.name.length > 64 || typeof stage.prompt !== "string" || !stage.prompt.trim() || stage.prompt.length > 4_000) fail(`Stage ${index + 1} needs a bounded name and prompt.`);
    if (!Number.isFinite(stage.experienceThreshold) || stage.experienceThreshold < threshold) fail("Growth thresholds must be monotonic.");
    if (index === 0 && stage.experienceThreshold !== 0) fail("The first growth threshold must be zero.");
    threshold = stage.experienceThreshold;
  });
  if (manifest.referenceFileName) {
    safeName(manifest.referenceFileName);
    if (!manifest.referenceFileName.toLowerCase().endsWith(".png") || files.has(manifest.referenceFileName.toLowerCase())) fail("referenceFileName must be a unique PNG file.");
  }
  if (manifest.contentHashes !== undefined && (!manifest.contentHashes || typeof manifest.contentHashes !== "object" || Array.isArray(manifest.contentHashes))) fail("contentHashes must be an object.");
  for (const [name, hash] of Object.entries(manifest.contentHashes ?? {})) {
    safeName(name);
    if (!/^[a-f0-9]{64}$/.test(hash)) fail(`contentHashes contains an invalid hash for ${name}.`);
  }
  return ["template.json", ...manifest.stages.map((stage) => stage.assetFileName), ...(manifest.referenceFileName ? [manifest.referenceFileName] : [])];
}

async function validatePNG(name, data, requireAlpha) {
  if (data.length < 32 || data.length > MAX_FILE_BYTES) fail(`${name} has an invalid file size.`);
  let metadata;
  try { metadata = await sharp(data, { failOn: "error" }).metadata(); } catch { fail(`${name} is corrupt.`); }
  if (metadata.format !== "png" || !metadata.width || !metadata.height || metadata.width < 32 || metadata.height < 32 || metadata.width > 4096 || metadata.height > 4096) fail(`${name} must be a valid 32–4096 px PNG.`);
  if (requireAlpha && !metadata.hasAlpha) fail(`${name} must include an alpha channel for desktop transparency.`);
}

async function readDirectory(directory) {
  const manifestFile = path.join(directory, "template.json");
  if (!existsSync(manifestFile)) fail("template.json is missing.");
  if ((await stat(manifestFile)).size > MAX_MANIFEST_BYTES) fail("template.json is too large.");
  const manifest = JSON.parse(await readFile(manifestFile, "utf8"));
  const expected = validateManifest(manifest);
  const actual = (await readdir(directory, { withFileTypes: true })).filter((entry) => entry.isFile()).map((entry) => entry.name).sort();
  const extras = actual.filter((name) => !expected.includes(name));
  if (extras.length) fail(`Unexpected files: ${extras.join(", ")}. Pet Packs cannot contain executable code or undeclared data.`);
  const files = new Map();
  for (const name of expected.slice(1)) {
    const file = path.join(directory, safeName(name));
    if (!existsSync(file) || !(await stat(file)).isFile()) fail(`Missing ${name}.`);
    const data = await readFile(file);
    await validatePNG(name, data, name !== manifest.referenceFileName);
    files.set(name, data);
  }
  return { manifest, files };
}

async function readPack(file) {
  const info = await stat(file);
  if (!info.isFile() || info.size > MAX_PACK_BYTES) fail("Pet Pack is larger than 96 MiB.");
  const data = await readFile(file);
  const zip = new AdmZip(data);
  const entries = zip.getEntries().filter((entry) => !entry.isDirectory);
  const names = new Set();
  let expanded = 0;
  for (const entry of entries) {
    safeName(entry.entryName);
    if (names.has(entry.entryName.toLowerCase())) fail(`Duplicate archive entry: ${entry.entryName}.`);
    names.add(entry.entryName.toLowerCase());
    if (!Number.isFinite(entry.header.size) || entry.header.size < 0) fail(`Invalid archive entry size: ${entry.entryName}.`);
    expanded += entry.header.size;
    const entryLimit = entry.entryName === "template.json" ? MAX_MANIFEST_BYTES : MAX_FILE_BYTES;
    if (entry.header.size > entryLimit || expanded > MAX_PACK_BYTES) fail("Expanded Pet Pack exceeds its safety budget.");
  }
  const manifestEntry = zip.getEntry("template.json");
  if (!manifestEntry) fail("template.json is missing.");
  if (manifestEntry.header.size > MAX_MANIFEST_BYTES) fail("template.json is too large.");
  const manifest = JSON.parse(manifestEntry.getData().toString("utf8"));
  const expected = validateManifest(manifest);
  const expectedLower = expected.map((name) => name.toLowerCase());
  const extras = entries.map((entry) => entry.entryName).filter((name) => !expectedLower.includes(name.toLowerCase()));
  if (extras.length) fail(`Unexpected entries: ${extras.join(", ")}. Pet Packs cannot contain executable code or undeclared data.`);
  const files = new Map();
  for (const name of expected.slice(1)) {
    const entry = zip.getEntry(name);
    if (!entry) fail(`Missing ${name}.`);
    const content = entry.getData();
    await validatePNG(name, content, name !== manifest.referenceFileName);
    files.set(name, content);
  }
  return { manifest, files };
}

function applyHashes(manifest, files) {
  return { ...manifest, contentHashes: Object.fromEntries([...files].map(([name, data]) => [name, sha256(data)])) };
}

function verifyHashes(manifest, files) {
  const actual = applyHashes(manifest, files).contentHashes;
  const expected = manifest.contentHashes;
  if (!expected || Object.keys(actual).length !== Object.keys(expected).length || Object.entries(actual).some(([name, hash]) => expected[name] !== hash)) fail("contentHashes do not match the declared files.");
}

async function init(directory) {
  if (existsSync(directory) && (await readdir(directory)).length) fail("Init target must be empty.");
  await mkdir(directory, { recursive: true });
  const manifest = {
    schemaVersion: SCHEMA,
    packFormat: FORMAT,
    minSidekinVersion: "2.2.0",
    id: `my-pack-${randomUUID().slice(0, 8)}`,
    name: "My Sidekin",
    author: "Your name",
    license: "Choose a license",
    motionProfile: "poised",
    contentHashes: {},
    basePrompt: "Describe one persistent nonhuman identity.",
    artDirection: "Readable premium game companion art.",
    generationMode: "text",
    generationQuality: "medium",
    referenceFileName: null,
    createdAt: new Date().toISOString(),
    fallbackTheme: "nova",
    stages: [{ id: "origin", index: 0, name: "Origin", prompt: "Describe this form.", experienceThreshold: 0, assetFileName: "stage-01.png" }]
  };
  await writeFile(path.join(directory, "template.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  process.stdout.write(`Initialized ${directory}. Add stage-01.png, then run validate and pack.\n`);
}

async function validate(input) {
  const directory = (await stat(input)).isDirectory();
  const result = directory ? await readDirectory(input) : await readPack(input);
  if (!directory || Object.keys(result.manifest.contentHashes ?? {}).length) verifyHashes(result.manifest, result.files);
  process.stdout.write(`Valid Pet Pack: ${result.manifest.name} · ${result.manifest.stages.length} stage${result.manifest.stages.length === 1 ? "" : "s"} · ${result.manifest.motionProfile}\n`);
}

async function pack(directory, output) {
  const { manifest, files } = await readDirectory(directory);
  const prepared = applyHashes(manifest, files);
  await writeFile(path.join(directory, "template.json"), `${JSON.stringify(prepared, null, 2)}\n`);
  const zip = new AdmZip();
  zip.addFile("template.json", Buffer.from(`${JSON.stringify(prepared, null, 2)}\n`));
  for (const [name, data] of files) zip.addFile(name, data);
  const packed = zip.toBuffer();
  if (packed.length > MAX_PACK_BYTES) fail("Packed file exceeds 96 MiB.");
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, packed);
  process.stdout.write(`Packed ${prepared.name} to ${output} (${(packed.length / 1024 / 1024).toFixed(1)} MiB).\n`);
}

async function unpack(input, directory) {
  if (existsSync(directory) && (await readdir(directory)).length) fail("Unpack target must be empty.");
  const { manifest, files } = await readPack(input);
  verifyHashes(manifest, files);
  await mkdir(directory, { recursive: true });
  await writeFile(path.join(directory, "template.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  for (const [name, data] of files) await writeFile(path.join(directory, safeName(name)), data);
  process.stdout.write(`Unpacked ${manifest.name} to ${directory}.\n`);
}

const [command, first, second] = process.argv.slice(2);
try {
  if (command === "init" && first) await init(path.resolve(first));
  else if (command === "validate" && first) await validate(path.resolve(first));
  else if (command === "pack" && first && second) await pack(path.resolve(first), path.resolve(second));
  else if (command === "unpack" && first && second) await unpack(path.resolve(first), path.resolve(second));
  else fail("Usage: pet-pack.mjs init <dir> | validate <dir|pack> | pack <dir> <file.sidekinpet> | unpack <file.sidekinpet> <dir>");
} catch (error) {
  process.stderr.write(`Pet Pack error: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
