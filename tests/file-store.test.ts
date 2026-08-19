import { existsSync } from "node:fs";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { atomicWrite, readJSON, writeJSON } from "../src/main/file-store.js";

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

describe("recoverable local persistence", () => {
  it("keeps a valid JSON backup and heals a corrupt primary file", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-store-"));
    roots.push(root);
    const file = path.join(root, "state.json");
    await writeJSON(file, { version: 1, progress: 42 });
    expect(existsSync(`${file}.bak`)).toBe(true);
    await writeFile(file, "{broken JSON", "utf8");

    expect(await readJSON(file)).toEqual({ version: 1, progress: 42 });
    expect(JSON.parse(await readFile(file, "utf8"))).toEqual({ version: 1, progress: 42 });
  });

  it("returns no data when both primary and backup are invalid", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-store-invalid-"));
    roots.push(root);
    const file = path.join(root, "settings.json");
    await writeFile(file, "not json", "utf8");
    await writeFile(`${file}.bak`, "also not json", "utf8");
    await expect(readJSON(file)).resolves.toBeUndefined();
  });

  it("does not leave temporary or rollback files after replacement", async () => {
    const root = await mkdtemp(path.join(tmpdir(), "sidekin-atomic-"));
    roots.push(root);
    const file = path.join(root, "asset.bin");
    await atomicWrite(file, Buffer.from("first"));
    await atomicWrite(file, Buffer.from("second"));
    expect(await readFile(file, "utf8")).toBe("second");
    await expect(readdir(root)).resolves.toEqual(["asset.bin"]);
  });
});
