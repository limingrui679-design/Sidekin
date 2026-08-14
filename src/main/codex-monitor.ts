import { existsSync, watch, type FSWatcher } from "node:fs";
import { app } from "electron";
import { appendFile, mkdir, open, readFile, readdir, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import type { CodexActivityRecord } from "../shared/codex.js";
import { inspectCodexLine, cleanSidekinHooks, containsSidekinHook, installSidekinHooks } from "../shared/codex.js";
import type { CodexActivity } from "../shared/types.js";
import type { SidekinPaths } from "./paths.js";

export class CodexMonitor {
  private timer?: NodeJS.Timeout;
  private watcher?: FSWatcher;
  private offsets = new Map<string, number>();
  private remainders = new Map<string, string>();
  private projects = new Map<string, string>();
  private sessionFiles: string[] = [];
  private lastDiscoveryAt = 0;
  private polling = false;

  constructor(
    private readonly paths: SidekinPaths,
    private readonly onActivity: (record: CodexActivityRecord) => void
  ) {}

  async start(): Promise<void> {
    await this.prime();
    this.timer = setInterval(() => void this.poll(), 850);
    if (existsSync(this.paths.codexSessions)) {
      try { this.watcher = watch(this.paths.codexSessions, { recursive: true }, () => void this.poll()); } catch { /* polling remains active */ }
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.watcher?.close();
    this.timer = undefined;
    this.watcher = undefined;
  }

  async isInstalled(): Promise<boolean> {
    if (!existsSync(this.paths.codexHooks)) return false;
    try { return containsSidekinHook(JSON.parse(await readFile(this.paths.codexHooks, "utf8"))); } catch { return false; }
  }

  async install(): Promise<void> {
    let root: Record<string, unknown> = {};
    if (existsSync(this.paths.codexHooks)) {
      const raw = JSON.parse(await readFile(this.paths.codexHooks, "utf8")) as unknown;
      if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("Existing hooks.json is not a JSON object and was left unchanged.");
      root = raw as Record<string, unknown>;
    }
    const bridge = process.execPath;
    const next = installSidekinHooks(root, bridge, process.platform, process.defaultApp ? app.getAppPath() : undefined);
    await mkdir(path.dirname(this.paths.codexHooks), { recursive: true });
    await writeFile(this.paths.codexHooks, `${JSON.stringify(next, null, 2)}\n`);
  }

  async uninstall(): Promise<void> {
    if (!existsSync(this.paths.codexHooks)) return;
    const raw = JSON.parse(await readFile(this.paths.codexHooks, "utf8")) as unknown;
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) throw new Error("Existing hooks.json is not a JSON object and was left unchanged.");
    await writeFile(this.paths.codexHooks, `${JSON.stringify(cleanSidekinHooks(raw as Record<string, unknown>), null, 2)}\n`);
  }

  async writeHookEvent(activity: CodexActivity, input: Buffer): Promise<void> {
    let hook: Record<string, unknown> = {};
    try { hook = JSON.parse(input.toString("utf8")) as Record<string, unknown>; } catch { /* optional metadata */ }
    const payload = {
      status: activity,
      timestamp: new Date().toISOString(),
      event_id: typeof hook.turn_id === "string" ? hook.turn_id : undefined,
      task_title: typeof hook.task_title === "string" ? hook.task_title : undefined,
      project: typeof hook.cwd === "string" ? path.basename(hook.cwd) : undefined
    };
    await mkdir(path.dirname(this.paths.eventInbox), { recursive: true });
    await appendFile(this.paths.eventInbox, `${JSON.stringify(payload)}\n`);
  }

  private async prime(): Promise<void> {
    const files = await this.recentSessionFiles();
    for (const file of [...files, this.paths.eventInbox]) this.offsets.set(file, await this.size(file));
    const latest = files[0];
    if (!latest) return;
    const content = await this.tail(latest, 512 * 1024);
    let record;
    for (const line of content.split("\n")) {
      const inspected = inspectCodexLine(line, { project: this.projects.get(latest) });
      if (inspected.project) this.projects.set(latest, inspected.project);
      if (inspected.record) record = inspected.record;
    }
    if (!record) return;
    const occurred = record.timestamp ?? new Date((await stat(latest)).mtimeMs);
    const age = Date.now() - occurred.getTime();
    if ((record.activity === "running" && age < 60 * 60 * 1_000) || (["completed", "failed"].includes(record.activity) && age < 15_000)) {
      this.onActivity({ ...record, timestamp: occurred });
    }
  }

  private async poll(): Promise<void> {
    if (this.polling) return;
    this.polling = true;
    try {
      if (Date.now() - this.lastDiscoveryAt > 5_000) {
        this.sessionFiles = await this.recentSessionFiles();
        this.lastDiscoveryAt = Date.now();
      }
      for (const file of [...this.sessionFiles].reverse()) await this.readNewLines(file);
      await this.readNewLines(this.paths.eventInbox);
    } finally {
      this.polling = false;
    }
  }

  private async readNewLines(file: string): Promise<void> {
    const size = await this.size(file);
    const previous = this.offsets.get(file) ?? 0;
    const offset = previous <= size ? previous : 0;
    if (size <= offset) { this.offsets.set(file, size); return; }
    try {
      const handle = await open(file, "r");
      const buffer = Buffer.alloc(size - offset);
      await handle.read(buffer, 0, buffer.length, offset);
      await handle.close();
      this.offsets.set(file, size);
      const chunk = (this.remainders.get(file) ?? "") + buffer.toString("utf8");
      const lines = chunk.split("\n");
      this.remainders.set(file, lines.pop() ?? "");
      for (const line of lines) {
        const inspected = inspectCodexLine(line, { project: this.projects.get(file) });
        if (inspected.project) this.projects.set(file, inspected.project);
        const record = inspected.record;
        if (record) this.onActivity(record);
      }
    } catch { this.offsets.set(file, size); }
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
    await walk(this.paths.codexSessions);
    return result.sort((a, b) => b.mtime - a.mtime).slice(0, 10).map((entry) => entry.file);
  }

  private async size(file: string): Promise<number> {
    try { return (await stat(file)).size; } catch { return 0; }
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
