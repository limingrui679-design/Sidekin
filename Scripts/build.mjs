import { build } from "esbuild";
import { cp, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const dist = path.join(root, "dist");

await rm(dist, { recursive: true, force: true });
await mkdir(path.join(dist, "main"), { recursive: true });
await mkdir(path.join(dist, "preload"), { recursive: true });
await mkdir(path.join(dist, "renderer"), { recursive: true });

const common = {
  bundle: true,
  sourcemap: true,
  logLevel: "info",
  target: "node22"
};

await build({
  ...common,
  entryPoints: [path.join(root, "src/main/index.ts")],
  outfile: path.join(dist, "main/index.cjs"),
  platform: "node",
  format: "cjs",
  external: ["electron", "sharp"]
});

await build({
  ...common,
  entryPoints: [path.join(root, "src/preload/index.ts")],
  outfile: path.join(dist, "preload/index.cjs"),
  platform: "node",
  format: "cjs",
  external: ["electron"]
});

for (const entry of ["app", "floating"]) {
  await build({
    bundle: true,
    sourcemap: true,
    minify: false,
    logLevel: "info",
    target: "chrome140",
    platform: "browser",
    format: "iife",
    entryPoints: [path.join(root, `src/renderer/${entry}.ts`)],
    outfile: path.join(dist, `renderer/${entry}.js`)
  });
}

for (const file of ["index.html", "floating.html", "styles.css", "floating.css"]) {
  await cp(path.join(root, "src/renderer", file), path.join(dist, "renderer", file));
}

console.log("Built Sidekin desktop runtime for Electron.");
