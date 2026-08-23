import AdmZip from "adm-zip";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import sharp from "sharp";
import { afterEach, describe, expect, it } from "vitest";

const execute = promisify(execFile);
const roots: string[] = [];
const cli = path.resolve("Scripts/pet-pack.mjs");

async function run(...args: string[]) {
  return execute(process.execPath, [cli, ...args], { cwd: path.resolve("."), maxBuffer: 2 * 1024 * 1024 });
}

async function image(color: string): Promise<Buffer> {
  return sharp({ create: { width: 96, height: 96, channels: 4, background: color } }).png().toBuffer();
}

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("Pet Pack SDK CLI", () => {
  it("initializes, validates, packs, verifies, and safely unpacks a data-only pack", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-pet-pack-"));
    roots.push(root);
    const source = path.join(root, "source");
    const packed = path.join(root, "sample.sidekinpet");
    const unpacked = path.join(root, "unpacked");
    await run("init", source);
    await writeFile(path.join(source, "stage-01.png"), await image("#6f4fe8"));
    expect((await run("validate", source)).stdout).toContain("Valid Pet Pack");
    expect((await run("pack", source, packed)).stdout).toContain("Packed");
    expect((await run("validate", packed)).stdout).toContain("Valid Pet Pack");
    expect((await run("unpack", packed, unpacked)).stdout).toContain("Unpacked");
    const manifest = JSON.parse(await readFile(path.join(unpacked, "template.json"), "utf8"));
    expect(manifest).toMatchObject({ schemaVersion: 2, packFormat: "sidekin.pet-pack", motionProfile: "poised" });
    expect(manifest.contentHashes["stage-01.png"]).toMatch(/^[a-f0-9]{64}$/);
  });

  it("rejects a valid PNG whose content no longer matches the signed manifest", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-pet-pack-tamper-"));
    roots.push(root);
    const source = path.join(root, "source");
    const packed = path.join(root, "sample.sidekinpet");
    const tampered = path.join(root, "tampered.sidekinpet");
    await run("init", source);
    await writeFile(path.join(source, "stage-01.png"), await image("#6f4fe8"));
    await run("pack", source, packed);
    const zip = new AdmZip(await readFile(packed));
    zip.updateFile("stage-01.png", await image("#ffcc44"));
    await writeFile(tampered, zip.toBuffer());
    await expect(run("validate", tampered)).rejects.toThrow(/contentHashes/);
  });

  it("matches the app boundary for transparent stages and supported pack versions", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-pet-pack-contract-"));
    roots.push(root);
    const source = path.join(root, "source");
    await run("init", source);
    const opaque = await sharp({ create: { width: 96, height: 96, channels: 3, background: "#334455" } }).png().toBuffer();
    await writeFile(path.join(source, "stage-01.png"), opaque);
    await expect(run("validate", source)).rejects.toThrow(/alpha channel/i);

    await writeFile(path.join(source, "stage-01.png"), await image("#334455"));
    const manifestFile = path.join(source, "template.json");
    const manifest = JSON.parse(await readFile(manifestFile, "utf8"));
    manifest.minSidekinVersion = "99.0.0";
    await writeFile(manifestFile, `${JSON.stringify(manifest, null, 2)}\n`);
    await expect(run("validate", source)).rejects.toThrow(/requires Sidekin 99\.0\.0/i);
  });
});
