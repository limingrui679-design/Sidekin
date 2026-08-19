import type { AgentProvider, CodexActivity } from "./types.js";

const HOOK_TIMEOUT_SECONDS = 10;

export interface AgentActivityRecord {
  activity: CodexActivity;
  provider: AgentProvider;
  timestamp?: Date;
  eventID?: string;
  sessionID?: string;
  title?: string;
  project?: string;
}
export type CodexActivityRecord = AgentActivityRecord;

export interface CodexSessionContext {
  project?: string;
}

function parseDate(raw: unknown): Date | undefined {
  if (typeof raw !== "string") return undefined;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function stringField(object: Record<string, unknown>, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const value = object[key];
    if (typeof value === "string") {
      const cleaned = value.replaceAll(/\p{Cc}/gu, " ").trim().slice(0, 160);
      if (cleaned) return cleaned;
    }
  }
  return undefined;
}

function projectFromPath(value: string | undefined): string | undefined {
  if (!value) return undefined;
  return value.replaceAll("\\", "/").split("/").filter(Boolean).at(-1)?.slice(0, 120);
}

function validActivity(raw: unknown): CodexActivity | undefined {
  return ["idle", "running", "completed", "failed"].includes(String(raw))
    ? raw as CodexActivity
    : undefined;
}

export function inspectCodexLine(
  line: string,
  context: CodexSessionContext = {}
): { record?: AgentActivityRecord; project?: string } {
  let object: Record<string, unknown>;
  try {
    object = JSON.parse(line) as Record<string, unknown>;
  } catch {
    return {};
  }


  if ((object.type === "session_meta" || object.type === "turn_context") && typeof object.payload === "object" && object.payload !== null) {
    const payload = object.payload as Record<string, unknown>;
    return { project: projectFromPath(stringField(payload, "cwd")) };
  }

  const direct = validActivity(object.status);
  if (direct) {
    return { record: {
      activity: direct,
      provider: object.provider === "claude" ? "claude" : "codex",
      timestamp: parseDate(object.timestamp),
      eventID: stringField(object, "event_id", "turn_id"),
      sessionID: stringField(object, "session_id"),
      project: stringField(object, "project", "workspace") ?? context.project
    } };
  }

  if (object.type !== "event_msg" || typeof object.payload !== "object" || object.payload === null) {
    return {};
  }
  const payload = object.payload as Record<string, unknown>;
  const activity: CodexActivity | undefined = payload.type === "task_started"
    ? "running"
    : payload.type === "task_complete"
      ? "completed"
      : ["turn_aborted", "task_failed", "stream_error", "error"].includes(String(payload.type))
        ? "failed"
        : undefined;
  if (!activity) return {};
  return { record: {
    activity,
    provider: "codex",
    timestamp: parseDate(object.timestamp) ?? parseDate(payload.completed_at) ?? parseDate(payload.started_at),
    eventID: stringField(payload, "turn_id", "id"),
    sessionID: stringField(payload, "session_id"),
    project: stringField(payload, "project", "workspace") ?? context.project
  } };
}

export function classifyCodexLine(line: string, context: CodexSessionContext = {}): AgentActivityRecord | undefined {
  return inspectCodexLine(line, context).record;
}

export function shellQuote(value: string, platform: NodeJS.Platform): string {
  if (platform === "win32") return `"${value.replaceAll('"', '\\"')}"`;
  return `'${value.replaceAll("'", "'\\''")}'`;
}

function cleanHooks(root: Record<string, unknown>, provider?: AgentProvider): Record<string, unknown> {
  const next = structuredClone(root);
  const hooks = typeof next.hooks === "object" && next.hooks !== null
    ? next.hooks as Record<string, unknown>
    : {};
  for (const event of ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"]) {
    const groups = Array.isArray(hooks[event]) ? hooks[event] as Array<Record<string, unknown>> : [];
    const cleaned = groups.flatMap((group) => {
      if (!Array.isArray(group.hooks)) return [group];
      const handlers = (group.hooks as Array<Record<string, unknown>>).filter((handler) => {
        const command = typeof handler.command === "string" ? handler.command : "";
        const legacyCodex = (!provider || provider === "codex") && (command.includes("SidekinBridge") || command.includes("CainiaoPetBridge"));
        const legacy = legacyCodex || (provider === "codex" && command.includes("sidekin-hook") && !command.includes("sidekin-hook claude"));
        const current = provider ? command.includes(`sidekin-hook ${provider}`) : command.includes("sidekin-hook");
        return !(legacy || current);
      });
      return handlers.length ? [{ ...group, hooks: handlers }] : [];
    });
    if (cleaned.length) hooks[event] = cleaned;
    else delete hooks[event];
  }
  next.hooks = hooks;
  return next;
}

export function cleanSidekinHooks(root: Record<string, unknown>): Record<string, unknown> { return cleanHooks(root); }
export function cleanSidekinProviderHooks(root: Record<string, unknown>, provider: AgentProvider): Record<string, unknown> { return cleanHooks(root, provider); }

export function installSidekinHooks(
  root: Record<string, unknown>,
  bridgeExecutable: string,
  platform: NodeJS.Platform,
  developmentAppPath?: string
): Record<string, unknown> {
  const next = cleanSidekinProviderHooks(root, "codex");
  const hooks = next.hooks as Record<string, unknown>;
  const command = `${shellQuote(bridgeExecutable, platform)}${developmentAppPath ? ` ${shellQuote(developmentAppPath, platform)}` : ""} sidekin-hook codex`;
  for (const [event, status] of [["UserPromptSubmit", "running"], ["Stop", "completed"]] as const) {
    const groups = Array.isArray(hooks[event]) ? hooks[event] as unknown[] : [];
    hooks[event] = [...groups, { hooks: [{ type: "command", command: `${command} ${status}`, timeout: HOOK_TIMEOUT_SECONDS }] }];
  }
  if (!next.description) {
    next.description = "Local Codex lifecycle hooks. Sidekin entries are added only after user confirmation.";
  }
  return next;
}

export function installClaudeHooks(
  root: Record<string, unknown>,
  bridgeExecutable: string,
  platform: NodeJS.Platform,
  developmentAppPath?: string
): Record<string, unknown> {
  const next = cleanSidekinProviderHooks(root, "claude");
  const hooks = next.hooks as Record<string, unknown>;
  const command = `${shellQuote(bridgeExecutable, platform)}${developmentAppPath ? ` ${shellQuote(developmentAppPath, platform)}` : ""} sidekin-hook claude`;
  for (const [event, status] of [["UserPromptSubmit", "running"], ["Stop", "completed"], ["StopFailure", "failed"], ["SessionEnd", "completed"]] as const) {
    const groups = Array.isArray(hooks[event]) ? hooks[event] as unknown[] : [];
    hooks[event] = [...groups, { hooks: [{ type: "command", command: `${command} ${status}`, timeout: HOOK_TIMEOUT_SECONDS }] }];
  }
  if (!next.description) next.description = "Local agent lifecycle hooks. Sidekin stores status metadata only.";
  return next;
}

export function containsSidekinHook(root: unknown): boolean {
  if (typeof root === "string") return root.includes("sidekin-hook") || root.includes("SidekinBridge");
  if (Array.isArray(root)) return root.some(containsSidekinHook);
  if (typeof root === "object" && root !== null) return Object.values(root).some(containsSidekinHook);
  return false;
}

export function containsSidekinProviderHook(root: unknown, provider: AgentProvider): boolean {
  if (typeof root === "string") return root.includes(`sidekin-hook ${provider}`) || (provider === "codex" && root.includes("SidekinBridge"));
  if (Array.isArray(root)) return root.some((value) => containsSidekinProviderHook(value, provider));
  if (typeof root === "object" && root !== null) return Object.values(root).some((value) => containsSidekinProviderHook(value, provider));
  return false;
}
