import { safeStorage } from "electron";
import { existsSync } from "node:fs";
import { readFile, rm } from "node:fs/promises";
import type { SidekinPaths } from "./paths.js";
import { atomicWrite } from "./file-store.js";

export class SecretStore {
  constructor(private readonly paths: SidekinPaths) {}

  async hasKey(): Promise<boolean> {
    return (await this.read()) !== undefined;
  }

  async read(): Promise<string | undefined> {
    if (!existsSync(this.paths.secret)) return undefined;
    try {
      if (!(await safeStorage.isAsyncEncryptionAvailable())) return undefined;
      const encrypted = await readFile(this.paths.secret);
      const decrypted = await safeStorage.decryptStringAsync(encrypted);
      const value = decrypted.result.trim();
      if (!value || value.length > 512 || /[\r\n\0]/.test(value)) return undefined;
      if (decrypted.shouldReEncrypt) {
        try { await atomicWrite(this.paths.secret, await safeStorage.encryptStringAsync(value)); }
        catch { /* keep the successfully decrypted credential for this session */ }
      }
      return value;
    } catch {
      // A corrupt or machine-moved credential must not prevent the local pet from starting.
      return undefined;
    }
  }

  async save(raw: string): Promise<void> {
    const key = raw.trim();
    if (!key) throw new Error("The API key cannot be empty.");
    if (!(await safeStorage.isAsyncEncryptionAvailable())) throw new Error("System credential encryption is unavailable.");
    await atomicWrite(this.paths.secret, await safeStorage.encryptStringAsync(key));
  }

  async remove(): Promise<void> {
    await rm(this.paths.secret, { force: true });
  }
}
