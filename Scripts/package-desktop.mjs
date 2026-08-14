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

if (!['darwin', 'win32'].includes(platform)) throw new Error("Sidekin desktop packaging supports macOS and Windows.");
if (!out.startsWith(`${root}${path.sep}`) || path.basename(out) !== "out") throw new Error("Refusing an unsafe package output path.");
await mkdir(out, { recursive: true });
await rm(make, { recursive: true, force: true });

const icon = path.join(root, "assets", "app-icon");

const applicationPaths = await packager({
  dir: root,
  out,
  name: "Sidekin",
  executableName: "Sidekin",
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
  extendInfo: { LSMinimumSystemVersion: "13.0" },
  win32metadata: {
    CompanyName: "Sidekin",
    FileDescription: "Sidekin live Codex companion",
    OriginalFilename: "Sidekin.exe",
    ProductName: "Sidekin"
  },
  osxSign: false,
  extraResource: [
    path.join(root, "ArtSources", "PET_THEME_CATALOG.json"),
    path.join(root, "Sources", "SidekinApp", "Resources", "Characters"),
    path.join(root, "assets", "tray-template.png")
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
  await run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", application]);
  await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", application]);
}

const resources = platform === "darwin"
  ? path.join(application, "Contents", "Resources")
  : path.join(packageDirectory, "resources");
const characters = path.join(resources, "Characters");
const characterFiles = (await readdir(characters)).filter((file) => file.endsWith(".png"));
if (characterFiles.length !== 500) throw new Error(`Packaged application contains ${characterFiles.length} character assets instead of 500.`);
for (const file of [path.join(resources, "PET_THEME_CATALOG.json"), path.join(resources, "tray-template.png"), path.join(resources, "app.asar")]) {
  if (!existsSync(file)) throw new Error(`Packaged application is missing ${path.basename(file)}.`);
}

const packageLabel = platform === "darwin" ? "macOS" : "Windows";
const archiveName = `Sidekin-${packageLabel}-${arch}.zip`;
let archive;
let archiveSHA256;
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
  if ((await stat(archive)).size < 1_000_000) throw new Error("Desktop archive is unexpectedly small.");
  archiveSHA256 = await new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    createReadStream(archive).on("error", reject).on("data", (chunk) => hash.update(chunk)).on("end", () => resolve(hash.digest("hex")));
  });
  await writeFile(`${archive}.sha256`, `${archiveSHA256}  ${archiveName}\n`);
}

await mkdir(make, { recursive: true });
const report = {
  schemaVersion: 1,
  product: "Sidekin",
  version,
  platform,
  arch,
  packageDirectory: path.relative(root, packageDirectory).split(path.sep).join("/"),
  application: path.relative(root, application).split(path.sep).join("/"),
  characterAssets: characterFiles.length,
  signing: platform === "darwin" ? "ad-hoc" : "unsigned",
  archive: archive ? path.relative(root, archive).split(path.sep).join("/") : null,
  archiveSHA256: archiveSHA256 ?? null
};
await writeFile(path.join(make, `package-report-${platform}-${arch}.json`), `${JSON.stringify(report, null, 2)}\n`);
console.log(`Packaged Sidekin ${version} for ${packageLabel} ${arch}: 500 assets${archive ? `, ${archiveName}` : ""}.`);
