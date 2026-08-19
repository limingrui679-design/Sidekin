import { existsSync, watch, type FSWatcher } from "node:fs";
import { app } from "electron";
import { appendFile, mkdir, open, readFile, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import type { AgentActivityRecord } from "../shared/codex.js";
import {
  cleanSidekinProviderHooks,
  containsSidekinProviderHook,
  inspectCodexLine,
  installClaudeHooks,
  installSidekinHooks
} from "../shared/codex.js";
import type { AgentActivity, AgentProvider, IntegrationStatus } from "../shared/types.js";
import { atomicWrite } from "./file-store.js";
import type { SidekinPaths } from "./paths.js";

const PROVIDER_NAMES: Record<AgentProvider, string> = { codex: "Codex", claude: "Claude Code" };
const MAX_EVENT_INBOX_BYTES = 2 * 1024 * 1024;

function metadata(value: unknown, maximum = 160): string | undefined {
  if (typeof value !== "string") return undefined;
  const cleaned = value.replaceAll(/\p{Cc}/gu, " ").trim().slice(0, maximum);
  return cleaned || undefined;
}

function workspaceBasename(value: unknown): string | undefined {
  const normalized = metadata(value, 2_048)?.replaceAll("\\", "/");
  return normalized?.split("/").filter(Boolean).at(-1)?.slice(0, 120);
}

export class CodexMonitor {
  private timer?: NodeJS.Timeout;
  private watcher?: FSWatcher;
  private offsets = new Map<string, number>();
  private remainders = new Map<string, string>();
  private projects = new Map<string, string>();
  private sessionFiles: string[] = [];
  private lastDiscoveryAt = 0;
  private polling = false;
  private monitorSessionLogs = true;
  private lastEventAt = new Map<AgentProvider, string>();
  private lastError = new Map<AgentProvider, string>();

  constructor(
    private readonly paths: SidekinPaths,
    private readonly onActivity: (record: AgentActivityRecord) => void
  ) {}

  async start(monitorSessionLogs = true): Promise<void> {
    this.monitorSessionLogs = monitorSessionLogs;
    await this.prime();
    this.timer = setInterval(() => void this.poll(), 850);
    this.configureWatcher();
  }

  async setSessionFallback(enabled: boolean): Promise<void> {
    if (this.monitorSessionLogs === enabled) return;
    this.monitorSessionLogs = enabled;
    this.watcher?.close();
    this.watcher = undefined;
    this.sessionFiles = [];
    if (enabled) {
      await this.primeSessions();
      this.configureWatcher();
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.watcher?.close();
    this.timer = undefined;
    this.watcher = undefined;
  }

  private configPath(provider: AgentProvider): string {
    return provider === "codex" ? this.paths.codexHooks : this.paths.claudeSettings;
  }

  async isInstalled(provider: AgentProvider): Promise<boolean> {
    const file = this.configPath(provider);
    if (!existsSync(file)) return false;
    try { return containsSidekinProviderHook(JSON.parse(await readFile(file, "utf8")), provider); }
    catch (error) {
      this.lastError.set(provider, error instanceof Error ? error.message : String(error));
      return false;
    }
  }

  async statuses(): Promise<IntegrationStatus[]> {
    const statuses = await Promise.all((["codex", "claude"] as AgentProvider[]).map(async (provider): Promise<IntegrationStatus> => {
      const installed = await this.isInstalled(provider);
      const mode = installed ? "hooks" : provider === "codex" && this.monitorSessionLogs ? "session-fallback" : "disconnected";
      return {
        provider,
        displayName: PROVIDER_NAMES[provider],
        installed,
        mode,
        lastEventAt: this.lastEventAt.get(provider) ?? null,
        lastError: this.lastError.get(provider)?.replaceAll(app.getPath("home"), "~") ?? null
      };
    }));
    return statuses;
  }

  async install(provider: AgentProvider): Promise<void> {
    const file = this.configPath(provider);
    let root: Record<string, unknown> = {};
    if (existsSync(file)) {
      const raw = JSON.parse(await readFile(file, "utf8")) as unknown;
      if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error(`Existing ${path.basename(file)} is not a JSON object and was left unchanged.`);
      root = raw as Record<string, unknown>;
    }
    const bridge = process.execPath;
    const developmentPath = process.defaultApp ? app.getAppPath() : undefined;
    const next = provider === "codex"
      ? installSidekinHooks(root, bridge, process.platform, developmentPath)
      : installClaudeHooks(root, bridge, process.platform, developmentPath);
    await mkdir(path.dirname(file), { recursive: true });
    await atomicWrite(file, `${JSON.stringify(next, null, 2)}\n`);
    this.lastError.delete(provider);
  }

  async uninstall(provider: AgentProvider): Promise<void> {
    const file = this.configPath(provider);
    if (!existsSync(file)) return;
    const raw = JSON.parse(await readFile(file, "utf8")) as unknown;
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error(`Existing ${path.basename(file)} is not a JSON object and was left unchanged.`);
    await atomicWrite(file, `${JSON.stringify(cleanSidekinProviderHooks(raw as Record<string, unknown>, provider), null, 2)}\n`);
    this.lastError.delete(provider);
  }

  async writeHookEvent(provider: AgentProvider, activity: AgentActivity, input: Buffer): Promise<void> {
    let hook: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(input.toString("utf8")) as unknown;
      if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) hook = parsed as Record<string, unknown>;
    } catch { /* optional metadata */ }
    const payload = {
      provider,
      status: activity,
      timestamp: new Date().toISOString(),
      event_id: provider === "codex" ? metadata(hook.turn_id) : undefined,
      session_id: metadata(hook.session_id),
      project: workspaceBasename(hook.cwd)
    };
    await this.withInboxLock(async () => {
      await appendFile(this.paths.eventInbox, `${JSON.stringify(payload)}\n`);
    });
  }

  private configureWatcher(): void {
    if (!this.monitorSessionLogs || !existsSync(this.paths.codexSessions)) return;
    try { this.watcher = watch(this.paths.codexSessions, { recursive: true }, () => void this.poll()); }
    catch (error) { this.lastError.set("codex", error instanceof Error ? error.message : String(error)); }
  }

  private async prime(): Promise<void> {
    await this.withInboxLock(async () => {
      const size = await this.size(this.paths.eventInbox);
      if (size > MAX_EVENT_INBOX_BYTES) {
        await atomicWrite(this.paths.eventInbox, "");
        this.offsets.set(this.paths.eventInbox, 0);
      } else {
        this.offsets.set(this.paths.eventInbox, size);
      }
    });
    if (this.monitorSessionLogs) await this.primeSessions();
  }

  private async primeSessions(): Promise<void> {
    const files = await this.recentSessionFiles();
    this.sessionFiles = files;
    for (const file of files) this.offsets.set(file, await this.size(file));
    const latest = files[0];
    if (!latest) return;
    const content = await this.tail(latest, 512 * 1024);
    let record: AgentActivityRecord | undefined;
    for (const line of content.split("\n")) {
      const inspected = inspectCodexLine(line, { project: this.projects.get(latest) });
      if (inspected.project) this.projects.set(latest, inspected.project);
      if (inspected.record) record = inspected.record;
    }
    if (!record) return;
    const occurred = record.timestamp ?? new Date((await stat(latest)).mtimeMs);
    const age = Date.now() - occurred.getTime();
    if ((record.activity === "running" && age < 30 * 60 * 1_000) || (["completed", "failed"].includes(record.activity) && age < 15_000)) this.emit({ ...record, timestamp: occurred });
  }

  private emit(record: AgentActivityRecord): void {
    this.lastEventAt.set(record.provider, (record.timestamp ?? new Date()).toISOString());
    this.lastError.delete(record.provider);
    this.onActivity(record);
  }

  private async poll(): Promise<void> {
    if (this.polling) return;
    this.polling = true;
    try {
      if (this.monitorSessionLogs && Date.now() - this.lastDiscoveryAt > 15_000) {
        this.sessionFiles = await this.recentSessionFiles();
        this.lastDiscoveryAt = Date.now();
      }
      if (this.monitorSessionLogs) for (const file of [...this.sessionFiles].reverse()) await this.readNewLines(file);
      await this.withInboxLock(() => this.readNewLines(this.paths.eventInbox, true));
    } finally {
      this.polling = false;
    }
  }

  private async readNewLines(file: string, compactAfterRead = false): Promise<void> {
    const size = await this.size(file);
    const previous = this.offsets.get(file) ?? 0;
    const offset = previous <= size ? previous : 0;
    if (size <= offset) {
      if (compactAfterRead && size > MAX_EVENT_INBOX_BYTES) {
        await atomicWrite(file, "");
        this.offsets.set(file, 0);
        this.remainders.delete(file);
      } else {
        this.offsets.set(file, size);
      }
      return;
    }
    try {
      const handle = await open(file, "r");
      const length = Math.min(size - offset, 2 * 1024 * 1024);
      const start = size - offset > length ? size - length : offset;
      const buffer = Buffer.alloc(length);
      await handle.read(buffer, 0, buffer.length, start);
      await handle.close();
      this.offsets.set(file, size);
      const chunk = (start === offset ? this.remainders.get(file) ?? "" : "") + buffer.toString("utf8");
      const lines = chunk.split("\n");
      this.remainders.set(file, lines.pop() ?? "");
      for (const line of lines) {
        const inspected = inspectCodexLine(line, { project: this.projects.get(file) });
        if (inspected.project) this.projects.set(file, inspected.project);
        if (inspected.record) this.emit(inspected.record);
      }
      if (compactAfterRead && size > MAX_EVENT_INBOX_BYTES) {
        await atomicWrite(file, "");
        this.offsets.set(file, 0);
        this.remainders.delete(file);
      }
    } catch (error) {
      this.offsets.set(file, size);
      this.lastError.set("codex", error instanceof Error ? error.message : String(error));
    }
  }

  private async recentSessionFiles(): Promise<string[]> {
    if (!existsSync(this.paths.codexSessions)) return [];
    const result: Array<{ file: string; mtime: number }> = [];
    const walk = async (directory: string): Promise<void> => {
      for (const entry of await readdir(directory, { withFileTypes: true })) {
        const file = path.join(directory, entry.name);
        if (entry.isDirectory()) await walk(file);
        else if (entry.isFile() && entry.name.endsWith(".jsonl")) result.push({ file, mtime: (await stat(file)).mtimeMs });
      }
    };
    try { await walk(this.paths.codexSessions); }
    catch (error) { this.lastError.set("codex", error instanceof Error ? error.message : String(error)); }
    return result.sort((a, b) => b.mtime - a.mtime).slice(0, 12).map((entry) => entry.file);
  }

  private async size(file: string): Promise<number> { try { return (await stat(file)).size; } catch { return 0; } }

  private async withInboxLock<T>(action: () => Promise<T>): Promise<T> {
    await mkdir(path.dirname(this.paths.eventInbox), { recursive: true });
    const lock = `${this.paths.eventInbox}.lock`;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      let handle;
      try {
        handle = await open(lock, "wx");
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        try {
          if (Date.now() - (await stat(lock)).mtimeMs > 30_000) await rm(lock, { force: true });
        } catch { /* another process released the lock */ }
        await new Promise((resolve) => setTimeout(resolve, 25));
        continue;
      }
      try {
        return await action();
      } finally {
        await handle.close();
        await rm(lock, { force: true });
      }
    }
    throw new Error("Sidekin could not acquire its local event-inbox lock.");
  }

  private async tail(file: string, length: number): Promise<string> {
    const size = await this.size(file);
    const handle = await open(file, "r");
    const buffer = Buffer.alloc(Math.min(size, length));
    await handle.read(buffer, 0, buffer.length, Math.max(0, size - buffer.length));
    await handle.close();
    return buffer.toString("utf8");
  }
}
