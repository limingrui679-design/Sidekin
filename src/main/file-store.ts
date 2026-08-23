import { existsSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";

const MAX_JSON_BYTES = 8 * 1024 * 1024;

async function readJSONFile<T>(file: string): Promise<{ parsed: T; source: string } | undefined> {
  if (!existsSync(file)) return undefined;
  try {
    if ((await stat(file)).size > MAX_JSON_BYTES) return undefined;
    const source = await readFile(file, "utf8");
    return { parsed: JSON.parse(source) as T, source };
  } catch {
    return undefined;
  }
}

export async function readJSON<T>(file: string): Promise<T | undefined> {
  const primary = await readJSONFile<T>(file);
  if (primary) return primary.parsed;
  const backup = await readJSONFile<T>(`${file}.bak`);
  if (!backup) return undefined;
  // Heal a missing or corrupt primary without replacing the known-good backup.
  await atomicWrite(file, backup.source);
  return backup.parsed;
}

export async function atomicWrite(file: string, value: string | Buffer): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  const nonce = `${process.pid}.${Date.now()}.${randomUUID()}`;
  const temporary = `${file}.${nonce}.tmp`;
  const rollback = `${file}.${nonce}.rollback`;
  await writeFile(temporary, value);
  let movedExisting = false;
  try {
    if (process.platform === "win32" && existsSync(file)) {
      await rename(file, rollback);
      movedExisting = true;
    }
    await rename(temporary, file);
    if (movedExisting) await rm(rollback, { force: true });
  } catch (error) {
    if (movedExisting && !existsSync(file) && existsSync(rollback)) await rename(rollback, file);
    throw error;
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function writeJSON(file: string, value: unknown): Promise<void> {
  const serialized = `${JSON.stringify(value, null, 2)}\n`;
  const previous = await readJSONFile<unknown>(file);
  if (previous) {
    await atomicWrite(`${file}.bak`, previous.source);
  } else if (!existsSync(`${file}.bak`)) {
    await atomicWrite(`${file}.bak`, serialized);
  }
  await atomicWrite(file, serialized);
}

export function safeIdentifier(value: string): string {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(value)) throw new Error("Unsafe identifier.");
  return value;
}

export function safeFileName(value: string): string {
  const base = path.basename(value);
  if (base !== value || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(value)) {
    throw new Error("Unsafe file name.");
  }
  return value;
}
