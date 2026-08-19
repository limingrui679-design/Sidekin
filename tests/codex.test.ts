import { describe, expect, it } from "vitest";
import { classifyCodexLine, cleanSidekinHooks, cleanSidekinProviderHooks, containsSidekinHook, containsSidekinProviderHook, inspectCodexLine, installClaudeHooks, installSidekinHooks } from "../src/shared/codex.js";

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

  it("quotes the Windows executable in hook commands", () => {
    const installed = installSidekinHooks({}, "C:\\Program Files\\Sidekin\\Sidekin.exe", "win32");
    expect(JSON.stringify(installed)).toContain("C:\\\\Program Files\\\\Sidekin\\\\Sidekin.exe");
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
