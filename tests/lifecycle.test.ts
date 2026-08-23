import { describe, expect, it, vi } from "vitest";
import { advance, applyActivity, careAvailability, clearInterruptedTasks, makeDefaultSnapshot, migrateSnapshot, performCare, stageProgress } from "../src/shared/lifecycle.js";

describe("shared pet lifecycle", () => {
  it("rewards meaningful care, enforces cooldowns, and evolves monotonically", () => {
    const now = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(now);
    pet.stats.hunger = 35;
    const first = performCare(pet, "feed", new Date(now.getTime() + 1_000));
    expect(first.rewarded).toBe(true);
    const blocked = performCare(first.snapshot, "feed", new Date(now.getTime() + 2_000));
    expect(blocked.rewarded).toBe(false);
    expect(blocked.snapshot.experience).toBe(5);
    blocked.snapshot.stats.hunger = 35;
    pet = performCare(blocked.snapshot, "feed", new Date(now.getTime() + 10 * 60_000 + 2_000)).snapshot;
    expect(pet.feedCount).toBe(2);
    pet = applyActivity(pet, "completed", { now: new Date(now.getTime() + 11 * 60_000), eventID: "turn-1" }).snapshot;
    pet = applyActivity(pet, "completed", { now: new Date(now.getTime() + 12 * 60_000), eventID: "turn-2" }).snapshot;
    expect(pet.experience).toBe(46);
    expect(pet.stage).toBe("hatchling");
    expect(pet.growthJournal.some((entry) => entry.type === "evolution")).toBe(true);
  });

  it("caps offline decay at twelve hours and wakes a fully rested pet", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    const pet = makeDefaultSnapshot(start);
    pet.isSleeping = true;
    pet.stats.energy = 5;
    const result = advance(pet, new Date("2026-08-15T00:00:00Z"));
    expect(result.stats.energy).toBe(100);
    expect(result.isSleeping).toBe(false);
    expect(result.stats.hunger).toBe(52);
  });

  it("deduplicates one completed Codex turn and maintains a bounded feed", () => {
    let pet = makeDefaultSnapshot(new Date("2026-08-13T00:00:00Z"));
    const first = applyActivity(pet, "completed", { now: new Date("2026-08-13T00:01:00Z"), eventID: "turn-1", title: "Build Sidekin", project: "Sidekin" });
    expect(first.applied).toBe(true);
    expect(first.snapshot.completedTasks).toBe(1);
    const duplicate = applyActivity(first.snapshot, "completed", { now: new Date("2026-08-13T00:02:00Z"), eventID: "turn-1" });
    expect(duplicate.applied).toBe(false);
    expect(duplicate.snapshot.completedTasks).toBe(1);

    pet = first.snapshot;
    for (let index = 2; index <= 9; index += 1) {
      pet = applyActivity(pet, "running", { now: new Date(`2026-08-13T00:${String(index).padStart(2, "0")}:00Z`), eventID: `turn-${index}` }).snapshot;
    }
    expect(pet.activityFeed).toHaveLength(8);
  });

  it("keeps the pet working while another task remains live", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(start);
    pet = applyActivity(pet, "running", { now: start, eventID: "turn-a", title: "A" }).snapshot;
    pet = applyActivity(pet, "running", { now: new Date(start.getTime() + 1_000), eventID: "turn-b", title: "B" }).snapshot;
    pet = applyActivity(pet, "completed", { now: new Date(start.getTime() + 2_000), eventID: "turn-a" }).snapshot;
    expect(pet.codexActivity).toBe("running");
    expect(pet.activityFeed.find((item) => item.id === "codex:turn-b")?.status).toBe("running");
  });

  it("migrates legacy branch stages without losing progress", () => {
    const pet = migrateSnapshot({ stage: "guardian" as never, experience: 90 });
    expect(pet.stage).toBe("ascended");
    expect(stageProgress(pet)).toBe(0);
  });

  it("drops retired cosmetic slots while preserving lineage selection", () => {
    const pet = migrateSnapshot({
      schemaVersion: 4,
      wardrobe: { theme: "nova", customTemplateID: null, hat: "cap", face: "visor", aura: "orbit" },
      cosmetics: { hat: "wizard", face: "glasses", aura: "sparkles" }
    } as never);
    expect(pet.schemaVersion).toBe(6);
    expect(pet).not.toHaveProperty("cosmetics");
    expect(pet.wardrobe).toEqual({ theme: "nova", customTemplateID: null });
  });

  it("sanitizes malformed local snapshots instead of carrying corrupt values into the UI", () => {
    const pet = migrateSnapshot({
      name: "\0".repeat(100),
      stats: { hunger: Number.NaN, mood: 5_000, energy: -50 },
      experience: -20,
      wardrobe: { theme: "../../escape", customTemplateID: "../template" },
      processedAgentSignals: Array.from({ length: 200 }, (_, index) => `signal-${index}`),
      activeTaskDays: ["not-a-date", "2026-08-13", "2026-08-13"],
      growthJournal: [{ type: "unknown", title: "bad" }],
      activityFeed: [
        { id: "task", title: "x".repeat(500), project: "p".repeat(500), status: "running", startedAt: "bad", updatedAt: "bad" },
        { status: "unknown" }
      ]
    }, new Date("2026-08-20T00:00:00Z"));
    expect(pet.name).toBe("Sprout");
    expect(pet.stats).toEqual({ hunger: 76, mood: 100, energy: 0 });
    expect(pet.experience).toBe(0);
    expect(pet.wardrobe).toEqual({ theme: "nova", customTemplateID: null });
    expect(pet.processedAgentSignals).toHaveLength(128);
    expect(pet.activeTaskDays).toEqual(["2026-08-13"]);
    expect(pet.growthJournal).toHaveLength(0);
    expect(pet.activityFeed).toHaveLength(1);
    expect(pet.activityFeed[0]?.title).toHaveLength(160);
    expect(pet.activityFeed[0]?.project).toHaveLength(120);
  });

  it("rotates through multiple idle motions", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(0));
    const pet = makeDefaultSnapshot();
    const motions = new Set<string>();
    for (const time of [0, 9_000, 18_000, 27_000]) {
      vi.setSystemTime(new Date(time));
      motions.add(applyActivity(pet, "idle", { deduplicate: false }).motion);
    }
    expect(motions.size).toBe(4);
    vi.useRealTimers();
  });

  it("keeps Codex and Claude Code sessions independent even when IDs collide", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(start);
    pet = applyActivity(pet, "running", { now: start, provider: "codex", eventID: "same", sessionID: "codex-session" }).snapshot;
    pet = applyActivity(pet, "running", { now: new Date(start.getTime() + 1_000), provider: "claude", eventID: "same", sessionID: "claude-session" }).snapshot;
    expect(pet.activityFeed.map((item) => item.id)).toEqual(["codex:same", "claude:same"]);
    pet = applyActivity(pet, "completed", { now: new Date(start.getTime() + 2_000), provider: "claude", eventID: "same", sessionID: "claude-session" }).snapshot;
    expect(pet.codexActivity).toBe("running");
    expect(pet.activityFeed.find((item) => item.id === "codex:same")?.status).toBe("running");
  });

  it("recovers stale running cards as interrupted and lets the user clear them", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = applyActivity(makeDefaultSnapshot(start), "running", { now: start, eventID: "lost-turn" }).snapshot;
    pet = advance(pet, new Date(start.getTime() + 2 * 60 * 60_000 + 1));
    expect(pet.activityFeed[0]?.status).toBe("interrupted");
    expect(pet.codexActivity).toBe("idle");
    expect(clearInterruptedTasks(pet).activityFeed).toHaveLength(0);
  });

  it("tracks consecutive active days and treats failure as small non-punitive growth", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(start);
    pet = applyActivity(pet, "completed", { now: new Date("2026-08-13T12:00:00Z"), eventID: "day-1" }).snapshot;
    pet = applyActivity(pet, "completed", { now: new Date("2026-08-14T12:00:00Z"), eventID: "day-2" }).snapshot;
    expect(pet.currentStreak).toBe(2);
    const before = pet.experience;
    pet = applyActivity(pet, "failed", { now: new Date("2026-08-14T12:01:00Z"), eventID: "failure" }).snapshot;
    expect(pet.experience).toBe(before + 4);
    expect(pet.failedTasks).toBe(1);
  });

  it("expires a focus streak after a full inactive day", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(start);
    pet = applyActivity(pet, "completed", { now: new Date("2026-08-13T12:00:00Z"), eventID: "day-1" }).snapshot;
    pet = applyActivity(pet, "completed", { now: new Date("2026-08-14T12:00:00Z"), eventID: "day-2" }).snapshot;
    expect(advance(pet, new Date("2026-08-15T12:00:00Z")).currentStreak).toBe(2);
    expect(advance(pet, new Date("2026-08-16T12:00:00Z")).currentStreak).toBe(0);
  });

  it("explains why a care action is unavailable", () => {
    const pet = makeDefaultSnapshot(new Date("2026-08-13T00:00:00Z"));
    pet.stats.hunger = 100;
    expect(careAvailability(pet).feed).toMatchObject({ available: false, reason: "Already comfortably full." });
  });
});
