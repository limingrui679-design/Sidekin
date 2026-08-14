import { existsSync } from "node:fs";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const requireCondition = (condition, message) => { if (!condition) throw new Error(message); };

for (const file of [
  "dist/main/index.cjs", "dist/preload/index.cjs", "dist/renderer/index.html",
  "dist/renderer/floating.html", "assets/app-icon.png", "assets/app-icon.ico"
]) requireCondition(existsSync(path.join(root, file)), `Missing desktop build artifact: ${file}`);

const packageJSON = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
requireCondition(packageJSON.version === "2.0.0", "Expected Sidekin 2.0.0 desktop version.");
requireCondition(packageJSON.devDependencies.electron, "Electron dependency is missing.");

const main = await readFile(path.join(root, "src/main/index.ts"), "utf8");
requireCondition(main.includes("transparent: true") && main.includes("alwaysOnTop: true"), "Floating window is not transparent and always-on-top.");
requireCondition(main.includes("contextIsolation: true") && main.includes("sandbox: true") && main.includes("nodeIntegration: false"), "Renderer security boundary is incomplete.");
requireCondition(main.includes("setPermissionRequestHandler") && main.includes("Content-Security-Policy"), "Permission or CSP gate is missing.");
requireCondition(main.includes("workshop.loadViews()") && main.includes("templates.loadViews()"), "Recovery preview data is not exposed to the shared UI.");

const retiredCosmeticSurface = (await Promise.all([
  "src/main/index.ts",
  "src/main/state-service.ts",
  "src/preload/index.ts",
  "src/shared/types.ts",
  "src/renderer/index.html",
  "src/renderer/app.ts",
  "src/renderer/floating.html",
  "src/renderer/floating.ts",
  "src/renderer/floating.css"
].map((file) => readFile(path.join(root, file), "utf8")))).join("\n");
for (const retiredIdentifier of [
  "sidekin:set-cosmetic", "setCosmetic", "hat-select", "face-select", "aura-select",
  "hat-slot", "face-slot", "aura-layer"
]) {
  requireCondition(!retiredCosmeticSurface.includes(retiredIdentifier), `Retired cosmetic surface remains: ${retiredIdentifier}`);
}
const lifecycle = await readFile(path.join(root, "src/shared/lifecycle.ts"), "utf8");
requireCondition(lifecycle.includes("schemaVersion: 5") && lifecycle.includes("delete current.cosmetics"), "Legacy cosmetic data is not removed during migration.");

const readme = await readFile(path.join(root, "README.md"), "utf8");
requireCondition(
  readme.includes('<a href="docs/readme/poster-arena-convergence.png"><img src="docs/readme/poster-arena-convergence.jpg"') && readme.includes('width="100%"'),
  "Arena Convergence must remain the full-width homepage poster."
);
const visualGallery = readme.split("## Visual gallery")[1]?.split("## At a glance")[0] ?? "";
requireCondition(!visualGallery.includes("<table>"), "Supporting posters must remain full-width instead of returning to a compact table.");
const supportingPosters = [
  ["Cosmic Grand Assembly", "hero-readme.jpg", "hero.jpg"],
  ["Evolution Odyssey", "poster-evolution-odyssey.jpg", "poster-evolution-odyssey.png"],
  ["Prismatic Pet Festival", "poster-prismatic-festival.jpg", "poster-prismatic-festival.png"],
  ["Chronicle of Ten Worlds", "poster-chronicle-ten-worlds.jpg", "poster-chronicle-ten-worlds.png"],
  ["Neon Night League", "poster-neon-night-league.jpg", "poster-neon-night-league.png"],
  ["Codex Companion Workshop", "poster-companion-workshop.jpg", "poster-companion-workshop.png"],
  ["Mythic Dawn Assembly", "poster-mythic-dawn.jpg", "poster-mythic-dawn.png"],
  ["Microverse Mayhem", "poster-microverse-mayhem.jpg", "poster-microverse-mayhem.png"]
];
for (const [title, preview, source] of supportingPosters) {
  requireCondition(visualGallery.includes(`### ${title}`), `Missing full-width supporting poster: ${title}`);
  requireCondition(existsSync(path.join(root, "docs/readme", preview)), `Missing README poster preview: ${preview}`);
  requireCondition(existsSync(path.join(root, "docs/readme", source)), `Missing full-resolution poster source: ${source}`);
}

const floatingCSS = await readFile(path.join(root, "src/renderer/floating.css"), "utf8");
const motions = ["idle-float", "idle-look", "idle-stretch", "idle-hop", "working-scan", "working-run", "celebrate", "fail", "feed", "play", "sleep", "wake", "evolve"];
requireCondition(motions.length === 13, "Expected exactly 13 named motion states.");
for (const motion of motions) {
  requireCondition(floatingCSS.includes(`.${motion}`), `Missing pet motion: ${motion}`);
}

const packaging = await readFile(path.join(root, "Scripts/package-desktop.mjs"), "utf8");
requireCondition(packaging.includes("@electron/packager") && packaging.includes("'darwin', 'win32'") && packaging.includes("zipRequested"), "macOS/Windows packaging is incomplete.");
requireCondition(packaging.includes('LSMinimumSystemVersion: "13.0"') && packaging.includes('"--sign", "-"'), "macOS source-Beta package metadata or ad-hoc signing is incomplete.");
requireCondition(packaging.includes('path.join("node_modules", "@img", "**", "*")'), "Sharp platform libraries must be unpacked beside the native module.");

const workshop = await readFile(path.join(root, "src/main/workshop.ts"), "utf8");
for (const gate of ["reprocessJobStage", "restartFromStage", "replaceTemplateStage", "regenerateTemplateStage", "reprocessTemplateRecovery"]) {
  requireCondition(workshop.includes(gate), `Missing shared workshop recovery feature: ${gate}`);
}

const codex = await readFile(path.join(root, "src/shared/codex.ts"), "utf8");
requireCondition(codex.includes('object.type === "session_meta"') && codex.includes('object.type === "turn_context"'), "Safe project-label metadata extraction is missing.");

const catalog = JSON.parse(await readFile(path.join(root, "ArtSources/PET_THEME_CATALOG.json"), "utf8"));
requireCondition(catalog.themes.length === 100, "Expected 100 built-in lineages.");
const assets = (await readdir(path.join(root, "Sources/SidekinApp/Resources/Characters"))).filter((file) => file.endsWith(".png"));
requireCondition(assets.length === 500, "Expected 500 built-in character assets.");
for (const theme of catalog.themes) {
  for (const stage of ["egg", "hatchling", "juvenile", "ascended", "legendary"]) {
    requireCondition(assets.includes(`${theme.id}-${stage}.png`), `Missing ${theme.id}-${stage}.png`);
  }
}

const workflow = await readFile(path.join(root, ".github/workflows/desktop.yml"), "utf8");
requireCondition(workflow.includes("macos-latest") && workflow.includes("windows-latest"), "Desktop CI must run on macOS and Windows.");
requireCondition(workflow.includes("npm run make") && workflow.includes("actions/upload-artifact@v4"), "Desktop CI must create and retain platform artifacts.");

console.log("Verified the Arena homepage poster, eight full-width themes, secure shared desktop runtime, retired cosmetic slots, 13 motions, 100 lineages, 500 forms, and macOS/Windows packaging gates.");
