import { packager } from "@electron/packager";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { createReadStream, existsSync } from "node:fs";
import { mkdir, readFile, readdir, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const run = promisify(execFile);
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const out = path.join(root, "out");
const make = path.join(out, "make");
const zipRequested = process.argv.includes("--zip");
const platform = process.platform;
const arch = process.arch;
const packageJSON = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
const version = packageJSON.version;

async function sha256File(file) {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    createReadStream(file)
      .on("error", reject)
      .on("data", (chunk) => hash.update(chunk))
      .on("end", () => resolve(hash.digest("hex")));
  });
}

if (!['darwin', 'win32'].includes(platform)) throw new Error("Sidekin desktop packaging supports macOS and Windows.");
if (!out.startsWith(`${root}${path.sep}`) || path.basename(out) !== "out") throw new Error("Refusing an unsafe package output path.");
await mkdir(out, { recursive: true });
await rm(make, { recursive: true, force: true });

const icon = path.join(root, "assets", platform === "darwin" ? "app-icon.icns" : "app-icon.ico");

const applicationPaths = await packager({
  dir: root,
  out,
  name: "Sidekin",
  executableName: "Sidekin",
  appVersion: "2.2.0",
  buildVersion: "9",
  platform,
  arch,
  overwrite: true,
  prune: true,
  asar: {
    unpack: "**/{.**,**}/**/*.node",
    unpackDir: path.join("node_modules", "@img", "**", "*")
  },
  icon,
  appBundleId: "app.sidekin.desktop",
  appCategoryType: "public.app-category.developer-tools",
  extendInfo: {
    LSMinimumSystemVersion: "13.0",
    NSAppTransportSecurity: { NSAllowsArbitraryLoads: false }
  },
  win32metadata: {
    CompanyName: "Sidekin",
    FileDescription: "Sidekin live coding-agent companion",
    OriginalFilename: "Sidekin.exe",
    ProductName: "Sidekin"
  },
  osxSign: false,
  extraResource: [
    path.join(root, "ArtSources", "PET_THEME_CATALOG.json"),
    path.join(root, "RuntimeAssets", "Characters"),
    path.join(root, "RuntimeAssets", "Thumbnails"),
    path.join(root, "RuntimeAssets", "manifest.json"),
    path.join(root, "assets", "tray-template.png"),
    path.join(root, "LICENSE"),
    path.join(root, "THIRD_PARTY_NOTICES.md")
  ],
  ignore: [
    /^\/ArtSources(?!\/PET_THEME_CATALOG\.json$)/,
    /^\/Sources/,
    /^\/artifacts/,
    /^\/docs/,
    /^\/tests/,
    /^\/src/,
    /^\/Scripts/,
    /^\/Support/,
    /^\/RuntimeAssets/,
    /^\/out/,
    /^\/\.git/,
    /^\/\.github/,
    /^\/\.build/,
    /^\/Package\.swift$/
  ]
});

if (applicationPaths.length !== 1) throw new Error(`Expected one packaged application, found ${applicationPaths.length}.`);
const packageDirectory = applicationPaths[0];
if (!packageDirectory || !existsSync(packageDirectory)) throw new Error("Packager did not create the application directory.");
const application = platform === "darwin"
  ? path.join(packageDirectory, "Sidekin.app")
  : path.join(packageDirectory, "Sidekin.exe");
if (!existsSync(application)) throw new Error("Packager did not create the application executable.");

if (platform === "darwin") {
  const packagedIcon = path.join(application, "Contents", "Resources", "electron.icns");
  if (!existsSync(packagedIcon) || !((await readFile(packagedIcon)).equals(await readFile(path.join(root, "assets", "app-icon.icns"))))) {
    throw new Error("Packaged macOS application does not contain the Sidekin icon.");
  }
  const infoPlist = path.join(application, "Contents", "Info.plist");
  const { stdout: allowsArbitraryLoads } = await run("/usr/bin/plutil", ["-extract", "NSAppTransportSecurity.NSAllowsArbitraryLoads", "raw", "-o", "-", infoPlist]);
  if (allowsArbitraryLoads.trim() !== "false") throw new Error("Packaged macOS application permits arbitrary network transport.");
  await run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", application]);
  await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", application]);
}

const resources = platform === "darwin"
  ? path.join(application, "Contents", "Resources")
  : path.join(packageDirectory, "resources");
const characters = path.join(resources, "Characters");
const thumbnails = path.join(resources, "Thumbnails");
const characterFiles = (await readdir(characters)).filter((file) => file.endsWith(".webp"));
const thumbnailFiles = (await readdir(thumbnails)).filter((file) => file.endsWith(".webp"));
if (characterFiles.length !== 1_000) throw new Error(`Packaged application contains ${characterFiles.length} character assets instead of 1,000.`);
if (thumbnailFiles.length !== 200) throw new Error(`Packaged application contains ${thumbnailFiles.length} thumbnails instead of 200.`);
for (const file of [path.join(resources, "PET_THEME_CATALOG.json"), path.join(resources, "manifest.json"), path.join(resources, "tray-template.png"), path.join(resources, "LICENSE"), path.join(resources, "THIRD_PARTY_NOTICES.md"), path.join(resources, "app.asar")]) {
  if (!existsSync(file)) throw new Error(`Packaged application is missing ${path.basename(file)}.`);
}

const sourceManifest = await readFile(path.join(root, "RuntimeAssets", "manifest.json"));
const packagedManifestFile = path.join(resources, "manifest.json");
const packagedManifestBytes = await readFile(packagedManifestFile);
if (!packagedManifestBytes.equals(sourceManifest)) throw new Error("Packaged runtime manifest differs from the verified source manifest.");
const packagedManifest = JSON.parse(packagedManifestBytes.toString("utf8"));
if (packagedManifest.schemaVersion !== 1 || !Array.isArray(packagedManifest.forms) || packagedManifest.forms.length !== 1_000) {
  throw new Error("Packaged runtime manifest has an invalid schema or form count.");
}
const expectedCharacters = packagedManifest.forms.map((record) => record.runtimeFile).sort();
const expectedThumbnails = packagedManifest.forms.filter((record) => record.thumbnailFile).map((record) => record.thumbnailFile).sort();
if (expectedCharacters.length !== 1_000 || expectedThumbnails.length !== 200) throw new Error("Packaged runtime manifest has invalid asset counts.");
if (characterFiles.sort().some((file, index) => file !== expectedCharacters[index])) throw new Error("Packaged character filenames differ from the runtime manifest.");
if (thumbnailFiles.sort().some((file, index) => file !== expectedThumbnails[index])) throw new Error("Packaged thumbnail filenames differ from the runtime manifest.");
let nextAsset = 0;
async function verifyPackagedAssetWorker() {
  while (true) {
    const index = nextAsset++;
    if (index >= packagedManifest.forms.length) return;
    const record = packagedManifest.forms[index];
    const runtimeFile = path.join(characters, record.runtimeFile);
    const runtimeInfo = await stat(runtimeFile);
    if (runtimeInfo.size !== record.runtimeBytes || await sha256File(runtimeFile) !== record.runtimeSHA256) {
      throw new Error(`Packaged runtime asset does not match its manifest: ${record.runtimeFile}`);
    }
    if (record.thumbnailFile) {
      const thumbnailFile = path.join(thumbnails, record.thumbnailFile);
      const thumbnailInfo = await stat(thumbnailFile);
      if (thumbnailInfo.size !== record.thumbnailBytes || await sha256File(thumbnailFile) !== record.thumbnailSHA256) {
        throw new Error(`Packaged thumbnail does not match its manifest: ${record.thumbnailFile}`);
      }
    }
  }
}
await Promise.all(Array.from({ length: 8 }, () => verifyPackagedAssetWorker()));

async function directoryBytes(directory) {
  let total = 0;
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) total += await directoryBytes(file);
    else if (entry.isFile()) total += (await stat(file)).size;
  }
  return total;
}

const applicationBytes = platform === "darwin" ? await directoryBytes(application) : await directoryBytes(packageDirectory);
if (applicationBytes > 450 * 1024 * 1024) throw new Error(`Unpacked application exceeds the 450 MiB source-Beta budget: ${(applicationBytes / 1_048_576).toFixed(1)} MiB.`);

const packageLabel = platform === "darwin" ? "macOS" : "Windows";
const archiveName = `Sidekin-${packageLabel}-${arch}.zip`;
let archive;
let archiveSHA256;
let archiveBytes;
if (zipRequested) {
  const destination = path.join(make, platform, arch);
  await mkdir(destination, { recursive: true });
  archive = path.join(destination, archiveName);
  await rm(archive, { force: true });
  const archiveTarget = platform === "darwin" ? application : packageDirectory;
  const parent = path.dirname(archiveTarget);
  const base = path.basename(archiveTarget);
  if (platform === "darwin") {
    await run("/usr/bin/zip", ["-qry", archive, base], { cwd: parent, env: { ...process.env, COPYFILE_DISABLE: "1" }, maxBuffer: 16 * 1024 * 1024 });
    const { stdout } = await run("/usr/bin/unzip", ["-Z1", archive], { maxBuffer: 128 * 1024 * 1024 });
    if (stdout.split("\n").some((entry) => entry.includes("__MACOSX") || entry.includes(".DS_Store") || entry.includes("/._"))) {
      throw new Error("Archive contains macOS metadata entries.");
    }
  } else {
    await run("tar.exe", ["-a", "-c", "-f", archive, base], { cwd: parent, maxBuffer: 16 * 1024 * 1024 });
  }
  archiveBytes = (await stat(archive)).size;
  if (archiveBytes < 1_000_000) throw new Error("Desktop archive is unexpectedly small.");
  archiveSHA256 = await sha256File(archive);
  if (archiveBytes > 350 * 1024 * 1024) throw new Error("Desktop ZIP exceeds the 350 MiB source-Beta budget.");
  await writeFile(`${archive}.sha256`, `${archiveSHA256}  ${archiveName}\n`);
}

await mkdir(make, { recursive: true });
const report = {
  schemaVersion: 2,
  product: "Sidekin",
  version,
  platform,
  arch,
  packageDirectory: path.relative(root, packageDirectory).split(path.sep).join("/"),
  application: path.relative(root, application).split(path.sep).join("/"),
  characterAssets: characterFiles.length,
  lineageThumbnails: thumbnailFiles.length,
  applicationBytes,
  applicationMiB: Number((applicationBytes / 1_048_576).toFixed(1)),
  signing: platform === "darwin" ? "ad-hoc" : "unsigned",
  archive: archive ? path.relative(root, archive).split(path.sep).join("/") : null,
  archiveBytes: archiveBytes ?? null,
  archiveMiB: archiveBytes ? Number((archiveBytes / 1_048_576).toFixed(1)) : null,
  archiveSHA256: archiveSHA256 ?? null
};
await writeFile(path.join(make, `package-report-${platform}-${arch}.json`), `${JSON.stringify(report, null, 2)}\n`);
console.log(`Packaged Sidekin ${version} for ${packageLabel} ${arch}: 1,000 assets, ${(applicationBytes / 1_048_576).toFixed(1)} MiB unpacked${archive ? `, ${archiveName}` : ""}.`);
