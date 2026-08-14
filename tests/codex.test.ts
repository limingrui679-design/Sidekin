import { describe, expect, it } from "vitest";
import { classifyCodexLine, cleanSidekinHooks, containsSidekinHook, inspectCodexLine, installSidekinHooks } from "../src/shared/codex.js";

describe("Codex lifecycle integration", () => {
  it("classifies direct bridge events with only minimal metadata", () => {
    expect(classifyCodexLine(JSON.stringify({ status: "running", timestamp: "2026-08-13T00:00:00Z", event_id: "turn-1", task_title: "Build", project: "Sidekin", prompt: "must remain unread" }))).toMatchObject({
      activity: "running", eventID: "turn-1", title: "Build", project: "Sidekin"
    });
  });

  it("classifies supported session events and ignores message content", () => {
    const record = classifyCodexLine(JSON.stringify({ type: "event_msg", timestamp: "2026-08-13T00:00:00Z", payload: { type: "task_complete", turn_id: "turn-2" }, message: "private" }));
    expect(record).toMatchObject({ activity: "completed", eventID: "turn-2" });
    expect(record).not.toHaveProperty("message");
    expect(classifyCodexLine(JSON.stringify({ type: "response_item", payload: { content: "private" } }))).toBeUndefined();
  });

  it("uses only safe working-directory metadata for the project label", () => {
    const context = inspectCodexLine(JSON.stringify({ type: "session_meta", payload: { cwd: "C:\\Users\\li\\Projects\\Sidekin", prompt: "private" } }));
    expect(context).toEqual({ project: "Sidekin" });
    expect(classifyCodexLine(JSON.stringify({ type: "event_msg", payload: { type: "task_started", turn_id: "turn-3", message: "private" } }), context)).toMatchObject({
      activity: "running", eventID: "turn-3", project: "Sidekin"
    });
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
});
