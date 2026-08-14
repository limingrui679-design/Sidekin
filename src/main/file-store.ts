import { existsSync } from "node:fs";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";

export async function readJSON<T>(file: string): Promise<T | undefined> {
  if (!existsSync(file)) return undefined;
  return JSON.parse(await readFile(file, "utf8")) as T;
}

export async function atomicWrite(file: string, value: string | Buffer): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  await writeFile(temporary, value);
  if (process.platform === "win32" && existsSync(file)) await rm(file, { force: true });
  await rename(temporary, file);
}

export async function writeJSON(file: string, value: unknown): Promise<void> {
  await atomicWrite(file, `${JSON.stringify(value, null, 2)}\n`);
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
