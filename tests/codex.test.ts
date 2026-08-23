import { describe, expect, it } from "vitest";
import { classifyCodexLine, cleanSidekinHooks, cleanSidekinProviderHooks, containsSidekinHook, containsSidekinProviderHook, inspectCodexLine, installClaudeHooks, installSidekinHooks } from "../src/shared/codex.js";

function decodeWindowsHook(command: string): string {
  const encoded = /-EncodedCommand\s+([A-Za-z0-9+/=]+)/i.exec(command)?.[1];
  if (!encoded) throw new Error("Windows hook does not contain an encoded PowerShell command.");
  return Buffer.from(encoded, "base64").toString("utf16le");
}

describe("Codex lifecycle integration", () => {
  it("classifies direct bridge events with only minimal metadata", () => {
    const record = classifyCodexLine(JSON.stringify({ status: "running", timestamp: "2026-08-13T00:00:00Z", event_id: "turn-1", task_title: "Secret task title", project: "Sidekin", prompt: "must remain unread" }));
    expect(record).toMatchObject({ activity: "running", provider: "codex", eventID: "turn-1", project: "Sidekin" });
    expect(record).not.toHaveProperty("title");
    expect(record).not.toHaveProperty("prompt");
  });

  it("classifies supported session events and ignores message content", () => {
    const record = classifyCodexLine(JSON.stringify({ type: "event_msg", timestamp: "2026-08-13T00:00:00Z", payload: { type: "task_complete", turn_id: "turn-2", title: "private title" }, message: "private" }));
    expect(record).toMatchObject({ activity: "completed", eventID: "turn-2" });
    expect(record).not.toHaveProperty("message");
    expect(record).not.toHaveProperty("title");
    expect(classifyCodexLine(JSON.stringify({ type: "response_item", payload: { content: "private" } }))).toBeUndefined();
  });

  it("uses only safe working-directory metadata for the project label", () => {
    const context = inspectCodexLine(JSON.stringify({ type: "session_meta", payload: { cwd: "C:\\Users\\example\\Projects\\Sidekin", prompt: "private" } }));
    expect(context).toEqual({ project: "Sidekin" });
    expect(classifyCodexLine(JSON.stringify({ type: "event_msg", payload: { type: "task_started", turn_id: "turn-3", message: "private" } }), context)).toMatchObject({
      activity: "running", eventID: "turn-3", project: "Sidekin"
    });
  });

  it("bounds lifecycle identifiers and workspace labels from untrusted event files", () => {
    const record = classifyCodexLine(JSON.stringify({ status: "running", event_id: "x".repeat(1_000), session_id: "s".repeat(1_000), project: "p".repeat(1_000) }));
    expect(record?.eventID).toHaveLength(160);
    expect(record?.sessionID).toHaveLength(160);
    expect(record?.project).toHaveLength(160);
  });

  it("preserves unrelated hooks during install and removal on macOS", () => {
    const original = { hooks: { Stop: [{ hooks: [{ type: "command", command: "backup-tool" }] }] } };
    const installed = installSidekinHooks(original, "/Applications/Sidekin.app/Contents/MacOS/Sidekin", "darwin");
    expect(containsSidekinHook(installed)).toBe(true);
    const cleaned = cleanSidekinHooks(installed);
    expect(containsSidekinHook(cleaned)).toBe(false);
    expect(JSON.stringify(cleaned)).toContain("backup-tool");
  });

  it("captures Windows Codex stdin through a bounded temporary-file bridge", () => {
    const installed = installSidekinHooks({}, "C:\\Program Files\\Sidekin\\Sidekin.exe", "win32");
    const hooks = installed.hooks as Record<string, Array<{ hooks: Array<{ command: string }> }>>;
    const runningCommand = hooks.UserPromptSubmit?.[0]?.hooks[0]?.command ?? "";
    const stopCommand = hooks.Stop?.[0]?.hooks[0]?.command ?? "";
    expect(runningCommand).toContain("powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand");
    const running = decodeWindowsHook(runningCommand);
    const stop = decodeWindowsHook(stopCommand);
    for (const script of [running, stop]) {
      expect(script).toContain("[Console]::In.ReadToEnd()");
      expect(script).toContain("[IO.File]::WriteAllText($hookFile");
      expect(script).toContain("'--hook-input-file', $hookFile");
      expect(script).toContain("& 'C:\\Program Files\\Sidekin\\Sidekin.exe' @sidekinArguments");
      expect(script).toContain("Remove-Item -LiteralPath $hookFile");
    }
    expect(running).toContain("@('sidekin-hook', 'codex', 'running'");
    expect(running).not.toContain("[Console]::Out.WriteLine('{}')");
    expect(stop).toContain("@('sidekin-hook', 'codex', 'completed'");
    expect(stop).toContain("[Console]::Out.WriteLine('{}')");
    expect(containsSidekinProviderHook(installed, "codex")).toBe(true);
    expect(containsSidekinProviderHook(cleanSidekinProviderHooks(installed, "codex"), "codex")).toBe(false);
  });

  it("uses the same Windows input bridge for Claude without Codex acknowledgement output", () => {
    const installed = installClaudeHooks({}, "C:\\Program Files\\Sidekin\\Sidekin.exe", "win32");
    const hooks = installed.hooks as Record<string, Array<{ hooks: Array<{ command: string }> }>>;
    const failed = decodeWindowsHook(hooks.StopFailure?.[0]?.hooks[0]?.command ?? "");
    expect(failed).toContain("@('sidekin-hook', 'claude', 'failed'");
    expect(failed).toContain("[Console]::In.ReadToEnd()");
    expect(failed).not.toContain("[Console]::Out.WriteLine('{}')");
    expect(containsSidekinProviderHook(installed, "claude")).toBe(true);
  });

  it("includes the source app path when hooks are installed from Electron development mode", () => {
    const installed = installSidekinHooks({}, "/Applications/Electron.app/Contents/MacOS/Electron", "darwin", "/Users/example/Projects/Sidekin");
    expect(JSON.stringify(installed)).toContain("'/Users/example/Projects/Sidekin' sidekin-hook");
  });

  it("classifies Claude bridge metadata without retaining prompt content", () => {
    const record = classifyCodexLine(JSON.stringify({ provider: "claude", status: "failed", session_id: "claude-session", project: "Sidekin", prompt: "private prompt", last_assistant_message: "private reply" }));
    expect(record).toMatchObject({ provider: "claude", activity: "failed", sessionID: "claude-session", project: "Sidekin" });
    expect(record).not.toHaveProperty("prompt");
    expect(record).not.toHaveProperty("last_assistant_message");
  });

  it("installs and removes each provider independently while preserving unrelated hooks", () => {
    const original = { hooks: { Stop: [{ hooks: [{ type: "command", command: "backup-tool" }] }] } };
    const codex = installSidekinHooks(original, "/Applications/Sidekin.app/Contents/MacOS/Sidekin", "darwin");
    const both = installClaudeHooks(codex, "/Applications/Sidekin.app/Contents/MacOS/Sidekin", "darwin");
    expect(containsSidekinProviderHook(both, "codex")).toBe(true);
    expect(containsSidekinProviderHook(both, "claude")).toBe(true);
    const noClaude = cleanSidekinProviderHooks(both, "claude");
    expect(containsSidekinProviderHook(noClaude, "claude")).toBe(false);
    expect(containsSidekinProviderHook(noClaude, "codex")).toBe(true);
    expect(JSON.stringify(noClaude)).toContain("backup-tool");
  });

  it("does not remove a legacy Codex bridge when disconnecting Claude Code", () => {
    const legacy = { hooks: { Stop: [{ hooks: [{ type: "command", command: "/Applications/SidekinBridge completed" }] }] } };
    const withClaude = installClaudeHooks(legacy, "/Applications/Sidekin.app/Contents/MacOS/Sidekin", "darwin");
    const noClaude = cleanSidekinProviderHooks(withClaude, "claude");
    expect(JSON.stringify(noClaude)).toContain("SidekinBridge");
    expect(containsSidekinProviderHook(noClaude, "claude")).toBe(false);
  });

  it("uses only officially supported Codex lifecycle events", () => {
    const installed = installSidekinHooks({}, "/Applications/Sidekin.app/Contents/MacOS/Sidekin", "darwin");
    expect(Object.keys(installed.hooks as object).sort()).toEqual(["Stop", "UserPromptSubmit"]);
    expect(JSON.stringify(installed)).not.toContain("StopFailure");
    expect(JSON.stringify(installed)).toContain('"timeout":10');
  });
});
