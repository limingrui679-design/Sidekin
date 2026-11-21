import { describe, expect, it } from "vitest";
import { applyActivity, makeDefaultSnapshot, migrateSnapshot } from "../src/shared/lifecycle.js";
import { remainingTime, restoreTiming, observeTiming, type TaskTimingSample } from "../src/shared/task-timing.js";

describe("conditional task timing", () => {
  const target = { id: "focus", startMs: 90 };

  it("conditions on having survived this long and handles tied censoring after endings", () => {
    const history = [1, 10, 20, 20, 20, { id: "open", startMs: 80 }, 40, 40, 80, 80, target];
    expect(remainingTime(history, "focus", 100)).toEqual({ atRisk: 8, medianMs: 30, p80Ms: 70 });
  });

  it("abstains on sparse support, unidentified tails and pre-start times", () => {
    const censored = Array.from({ length: 8 }, (_, i) => ({ id: String(i), startMs: 50 }));
    expect(remainingTime([...censored, target], "focus", 100)).toBeNull();
    expect(remainingTime([...Array(7).fill(20), target], "focus", 100)).toBeNull();
    expect(remainingTime([...Array(8).fill(20), target], "focus", 89)).toBeNull();
    expect(remainingTime([20, 20, 20, 20, ...censored.slice(0, 4), target], "focus", 100))
      .toEqual({ atRisk: 8, medianMs: 10, p80Ms: null });
  });

  it("evicts by observed start order and ignores missing or contradictory timing pairs", () => {
    let history: TaskTimingSample[] = [];
    for (let i = 0; i < 130; i++) history = observeTiming(history, String(i), "running", i);
    expect(history).toHaveLength(128);
    expect(observeTiming(history, "0", "completed", 500)).toBe(history);
    history = observeTiming(history, "2", "failed", 502);
    expect(history[0]).toBe(500);
    expect(observeTiming(history, "2", "completed", 503)).toBe(history);
    expect(observeTiming(history, "3", "completed", 1)).toHaveLength(127);
    expect(restoreTiming([null, -1, {}, NaN, { id: "x", startMs: 3, title: "omit" }, 5]))
      .toEqual([{ id: "x", startMs: 3 }, 5]);
  });

  it("records real paired signals across feed eviction and restart, excluding previews", () => {
    let pet = makeDefaultSnapshot(new Date(0));
    for (let i = 0; i < 7; i++) pet = applyActivity(pet, "running", { eventID: String(i), now: new Date(i) }).snapshot;
    pet = migrateSnapshot(JSON.parse(JSON.stringify(pet)));
    pet = applyActivity(pet, "completed", { eventID: "0", now: new Date(70) }).snapshot;
    expect(pet.activityFeed.find(item => item.id === "0")?.durationMs).toBe(70);
    pet = applyActivity(pet, "failed", { eventID: "0", now: new Date(71) }).snapshot;
    pet = applyActivity(pet, "running", { eventID: "preview", now: new Date(72), trackTiming: false }).snapshot;
    expect(pet.taskTimings?.filter(x => typeof x === "number")).toEqual([70]);
    expect(pet.taskTimings).toHaveLength(7);
    expect(migrateSnapshot({ activityFeed: [] }).taskTimings).toEqual([]);
  });
});
