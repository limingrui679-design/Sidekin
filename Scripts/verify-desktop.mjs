import { existsSync } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const requireCondition = (condition, message) => { if (!condition) throw new Error(message); };
const text = async (file) => readFile(path.join(root, file), "utf8");

for (const file of [
  "dist/main/index.cjs", "dist/preload/index.cjs", "dist/renderer/index.html",
  "dist/renderer/floating.html", "assets/app-icon.png", "assets/app-icon.ico",
  "RuntimeAssets/manifest.json", "docs/ART_ARCHIVE.md", "docs/PET_PACK_SDK.md",
  "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SUPPORT.md", "CHANGELOG.md",
  "SECURITY.md", "THIRD_PARTY_NOTICES.md", "docs/PRIVACY.md", "docs/THREAT_MODEL.md",
  "docs/RELEASE_NOTES_2.2.0-beta.1.md", ".github/ISSUE_TEMPLATE/bug.yml",
  ".github/ISSUE_TEMPLATE/feature.yml", ".github/pull_request_template.md"
]) requireCondition(existsSync(path.join(root, file)), `Missing desktop artifact: ${file}`);

const packageJSON = JSON.parse(await text("package.json"));
requireCondition(packageJSON.version === "2.2.0-beta.1", "Expected Sidekin 2.2.0-beta.1.");
requireCondition(packageJSON.engines?.node === ">=22.12 <23", "Node 22.12+ must be the reproducible development and CI runtime.");
requireCondition(packageJSON.scripts.verify.includes("run-e2e.mjs") && packageJSON.scripts.verify.includes("assets:verify"), "Top-level verification must include real Electron E2E and runtime assets.");

const infoPlist = await text("Support/Info.plist");
for (const contract of ["<string>2.2.0</string>", "<string>13.0</string>", "<string>9</string>"]) {
  requireCondition(infoPlist.includes(contract), `Historical macOS metadata is inconsistent: ${contract}`);
}
const security = await text("SECURITY.md");
requireCondition(security.includes("2.2.0-beta.x") && security.includes("security/advisories/new"), "Security support and private reporting must target 2.2.");
const privacy = await text("docs/PRIVACY.md");
const threatModel = await text("docs/THREAT_MODEL.md");
requireCondition(privacy.includes("no telemetry") && privacy.includes("Reference-selection tokens expire after 30 minutes"), "Privacy inventory or retention contract is incomplete.");
requireCondition(threatModel.includes("Residual risks") && threatModel.includes("sandboxed local renderers"), "Threat model must document trust boundaries and residual risk.");

const main = await text("src/main/index.ts");
for (const gate of [
  "transparent: true", "alwaysOnTop: true", "contextIsolation: true", "sandbox: true", "nodeIntegration: false",
  "setPermissionRequestHandler", "Content-Security-Policy", "assertTrustedSender", "assertGenerationRequest",
  "requestSingleInstanceLock", "clampFloatingBounds", "referenceSelections", "setIgnoreMouseEvents",
  "protocol.handle(\"sidekin-media\"", "realpath(path.join(root, ...relative))", "isAllowedMediaFile",
  'stage.assetFileName === fileName', '/^(raw|processed)-stage-0[1-8]\\.png$/'
]) requireCondition(main.includes(gate), `Missing desktop/security gate: ${gate}`);
requireCondition(main.includes('bridgeInvocation || app.requestSingleInstanceLock()'), "Hook bridge processes must bypass the UI single-instance lock.");
requireCondition(main.includes('process.argv.includes("--hidden")') && main.includes('args: ["--hidden"]'), "Launch-at-login must not force the Command Center open.");
requireCondition(main.includes('normalized === pathToFileURL(rendererFile(file)).href'), "Renderer sender trust must match exact local files.");
requireCondition(main.includes("img-src 'self' sidekin-media: data:") && !main.includes("img-src 'self' file:"), "Renderer image CSP must use the allowlisted media protocol instead of file URLs.");

const surfaceFiles = [
  "src/main/index.ts", "src/main/state-service.ts", "src/preload/index.ts", "src/shared/types.ts",
  "src/renderer/index.html", "src/renderer/app.ts", "src/renderer/floating.html", "src/renderer/floating.ts", "src/renderer/floating.css"
];
const surface = (await Promise.all(surfaceFiles.map(text))).join("\n");
for (const retired of ["sidekin:set-cosmetic", "setCosmetic", "hat-select", "face-select", "aura-select", "hat-slot", "face-slot", "aura-layer"]) {
  requireCondition(!surface.includes(retired), `Retired cosmetic surface remains: ${retired}`);
}
requireCondition(!(await text("src/renderer/app.ts")).includes("referencePath"), "The untrusted renderer still exposes a local reference path.");
requireCondition(!main.includes("codexHooks: paths.codexHooks") && !(await text("src/shared/types.ts")).includes("codexSessions: string"), "The bootstrap payload must not expose absolute agent or user-data paths.");
requireCondition((await text("src/main/state-service.ts")).includes("private publicPet()") && (await text("src/main/template-store.ts")).includes("generationQuality: template.generationQuality") && !(await text("src/main/workshop.ts")).includes("...job,"), "Renderer payloads must use explicit minimized view models.");
for (const file of ["src/main/state-service.ts", "src/main/template-store.ts", "src/main/workshop.ts"]) {
  requireCondition(!(await text(file)).includes("pathToFileURL"), `${file} still exposes absolute asset paths to a renderer.`);
}

const lifecycle = await text("src/shared/lifecycle.ts");
for (const feature of ["schemaVersion: 6", "CARE_COOLDOWNS", "RUNNING_STALE_AFTER_MS", "growthJournal", "currentStreak", "temperamentFor", "clearInterruptedTasks"]) {
  requireCondition(lifecycle.includes(feature), `Missing lifecycle 2.2 feature: ${feature}`);
}
requireCondition(!lifecycle.includes("current.cosmetics") && !lifecycle.includes("cosmetics:"), "Retired cosmetic state remains in the lifecycle migration.");

const codex = await text("src/shared/codex.ts");
for (const feature of ["installSidekinHooks", "installClaudeHooks", "cleanSidekinProviderHooks", 'sidekin-hook codex', 'sidekin-hook claude']) {
  requireCondition(codex.includes(feature), `Missing agent integration feature: ${feature}`);
}
requireCondition(codex.includes('["UserPromptSubmit", "running"], ["Stop", "completed"]'), "Codex hooks must use the supported lifecycle pair.");
const monitor = await text("src/main/codex-monitor.ts");
requireCondition(monitor.includes("2 * 1024 * 1024") && monitor.includes("15_000") && monitor.includes("lastError"), "Agent monitor must be bounded and diagnostic.");

const floatingCSS = await text("src/renderer/floating.css");
const motions = ["idle-float", "idle-look", "idle-stretch", "idle-hop", "working-scan", "working-run", "celebrate", "fail", "feed", "play", "sleep", "wake", "evolve"];
const profiles = ["agile", "bouncing", "buoyant", "flowing", "gliding", "heavy", "marching", "mechanical", "orbiting", "poised", "prowling", "pulsing", "rolling", "rooted", "serpentine", "skittering", "spectral", "swarming", "swimming", "winged"];
for (const motion of motions) requireCondition(floatingCSS.includes(`.${motion}`), `Missing lifecycle motion: ${motion}`);
for (const profile of profiles) requireCondition(floatingCSS.includes(`profile-${profile}`), `Missing motion profile: ${profile}`);
requireCondition(floatingCSS.includes("prefers-reduced-motion"), "Floating companion lacks reduced-motion behavior.");

const html = await text("src/renderer/index.html");
const styles = await text("src/renderer/styles.css");
for (const contract of ['lang="en"', 'aria-live="polite"', '<progress class="progress-track"', 'aria-label="Command Center sections"', 'id="integration-list"', 'id="growth-journal"']) {
  requireCondition(html.includes(contract), `Missing accessibility/product contract: ${contract}`);
}
requireCondition(styles.includes(":focus-visible") && styles.includes("prefers-reduced-motion"), "Command Center lacks keyboard focus or reduced-motion CSS.");
requireCondition(html.includes('data-title="Pet Workshop"') && (await text("src/renderer/app.ts")).includes("dataset.title"), "Page titles must not inherit decorative navigation glyphs.");
requireCondition(styles.includes('.toggle-row input[type="checkbox"]:checked'), "Settings must use a consistent cross-platform switch treatment.");
requireCondition(!(await text("src/renderer/app.ts")).includes('setAttribute("style"'), "Renderer progress updates must not violate the strict style CSP.");

const catalog = JSON.parse(await text("ArtSources/PET_THEME_CATALOG.json"));
requireCondition(catalog.schemaVersion === 2 && catalog.themes.length === 200, "Expected the 200-lineage schema-2 catalog.");
requireCondition(catalog.themes.every((theme) => Array.isArray(theme.tags) && theme.tags.length >= 3 && profiles.includes(theme.motionProfile)), "Catalog tags or motion profiles are invalid.");
const runtimeFiles = (await readdir(path.join(root, "RuntimeAssets", "Characters"))).filter((file) => file.endsWith(".webp"));
const thumbnails = (await readdir(path.join(root, "RuntimeAssets", "Thumbnails"))).filter((file) => file.endsWith(".webp"));
requireCondition(runtimeFiles.length === 1_000 && thumbnails.length === 200, "Expected 1,000 runtime forms and 200 thumbnails.");
requireCondition(!existsSync(path.join(root, "Sources", "SidekinApp", "Resources", "Characters")), "Full PNG corpus must stay off the optimized main branch.");

const readme = await text("README.md");
requireCondition(readme.includes('src="docs/readme/poster-arena-convergence.jpg"') && readme.includes('width="100%"'), "Arena Convergence must remain the full-width homepage poster.");
for (const title of ["Cosmic Grand Assembly", "Evolution Odyssey", "Prismatic Pet Festival", "Chronicle of Living Worlds", "Neon Night League", "Codex Companion Workshop", "Mythic Dawn Assembly", "Microverse Mayhem"]) {
  requireCondition(readme.includes(`### ${title}`), `Missing supporting poster: ${title}`);
}
for (const preview of ["hero-readme.jpg", "poster-evolution-odyssey.jpg", "poster-prismatic-festival.jpg", "poster-chronicle-ten-worlds.jpg", "poster-neon-night-league.jpg", "poster-companion-workshop.jpg", "poster-mythic-dawn.jpg", "poster-microverse-mayhem.jpg", "all-200-readme.jpg"]) {
  requireCondition(existsSync(path.join(root, "docs", "readme", preview)), `Missing lightweight README preview: ${preview}`);
}
for (const removed of ["all-200.jpg", "hero.jpg", "poster-arena-convergence.png", "showcase-20.jpg"]) {
  requireCondition(!existsSync(path.join(root, "docs", "readme", removed)), `Full-resolution README source remains on main: ${removed}`);
}

const petPack = await text("Scripts/pet-pack.mjs");
for (const contract of ["contentHashes", "Unexpected entries", "Duplicate archive entry", "Expanded Pet Pack", "motionProfile"]) {
  requireCondition(petPack.includes(contract), `Pet Pack safety contract is missing: ${contract}`);
}

const packaging = await text("Scripts/package-desktop.mjs");
for (const contract of ["@electron/packager", "'darwin', 'win32'", "appVersion: \"2.2.0\"", "buildVersion: \"9\"", "NSAllowsArbitraryLoads: false", "Packaged macOS application does not contain the Sidekin icon", "THIRD_PARTY_NOTICES.md", "450 * 1024 * 1024", "350 * 1024 * 1024", "/^\\/RuntimeAssets/", "verifyPackagedAssetWorker", "archiveSHA256"]) {
  requireCondition(packaging.includes(contract), `Packaging contract is missing: ${contract}`);
}

const workflow = await text(".github/workflows/desktop.yml");
for (const contract of ["macos-latest", "windows-latest", "npm ci", "npm run make", "npm audit --audit-level=high", "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a"]) {
  requireCondition(workflow.includes(contract), `Desktop CI contract is missing: ${contract}`);
}

const runtimeBytes = (await stat(path.join(root, "RuntimeAssets", "manifest.json"))).size
  + (await Promise.all(runtimeFiles.map((file) => stat(path.join(root, "RuntimeAssets", "Characters", file))))).reduce((sum, item) => sum + item.size, 0)
  + (await Promise.all(thumbnails.map((file) => stat(path.join(root, "RuntimeAssets", "Thumbnails", file))))).reduce((sum, item) => sum + item.size, 0);
requireCondition(runtimeBytes < 135 * 1024 * 1024, "Runtime catalog exceeds the 135 MiB repository budget.");

console.log(`Verified Sidekin 2.2: secure cross-platform runtime, Codex + Claude adapters, schema-6 care/growth, 13×20 motion system, Pet Pack SDK, lightweight README, 200 lineages, 1,200 runtime media files, E2E and package/CI budgets (${(runtimeBytes / 1_048_576).toFixed(1)} MiB catalog).`);
