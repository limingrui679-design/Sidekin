import { describe, expect, it, vi } from "vitest";
import { advance, applyActivity, makeDefaultSnapshot, migrateSnapshot, performCare, stageProgress } from "../src/shared/lifecycle.js";

describe("shared pet lifecycle", () => {
  it("uses the original care balance and evolves monotonically", () => {
    const now = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(now);
    for (let index = 0; index < 3; index += 1) pet = performCare(pet, "feed", new Date(now.getTime() + index + 1)).snapshot;
    expect(pet.experience).toBe(21);
    expect(pet.stage).toBe("hatchling");
    expect(pet.feedCount).toBe(3);
  });

  it("caps offline decay at twelve hours and wakes a fully rested pet", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    const pet = makeDefaultSnapshot(start);
    pet.isSleeping = true;
    pet.stats.energy = 5;
    const result = advance(pet, new Date("2026-08-15T00:00:00Z"));
    const sleeping = (99 - 5) / 18;
    const awake = 12 - sleeping;
    expect(result.stats.energy).toBeCloseTo(99 - awake * 2.2);
    expect(result.isSleeping).toBe(false);
    expect(result.stats.hunger).toBeCloseTo(pet.stats.hunger - sleeping * 2 - awake * 4);
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
    expect(pet.activityFeed).toHaveLength(5);
  });

  it("keeps the pet working while another task remains live", () => {
    const start = new Date("2026-08-13T00:00:00Z");
    let pet = makeDefaultSnapshot(start);
    pet = applyActivity(pet, "running", { now: start, eventID: "turn-a", title: "A" }).snapshot;
    pet = applyActivity(pet, "running", { now: new Date(start.getTime() + 1_000), eventID: "turn-b", title: "B" }).snapshot;
    pet = applyActivity(pet, "completed", { now: new Date(start.getTime() + 2_000), eventID: "turn-a" }).snapshot;
    expect(pet.codexActivity).toBe("running");
    expect(pet.activityFeed.find((item) => item.id === "turn-b")?.status).toBe("running");
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
    expect(pet.schemaVersion).toBe(5);
    expect(pet).not.toHaveProperty("cosmetics");
    expect(pet.wardrobe).toEqual({ theme: "nova", customTemplateID: null });
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
});

it("integrates sleep and waking identically across one offline gap or many ticks", () => {
  const start = Date.UTC(2026, 0, 1);
  const pet = makeDefaultSnapshot(new Date(start));
  pet.isSleeping = true;
  pet.stats = { hunger: 80, mood: 99.8, energy: 81 };
  const at = (hours: number) => new Date(start + hours * 3_600_000);
  const offline = advance(pet, at(4));
  let ticking = pet;
  for (let tick = 1; tick <= 16; tick++) ticking = advance(ticking, at(tick / 4));
  expect(offline.isSleeping).toBe(false);
  expect(offline.stats.energy).toBeCloseTo(92.4);
  expect(offline.stats.mood).toBeCloseTo(96.1);
  expect(offline.stats.hunger).toBeCloseTo(66);
  for (const key of ["energy", "hunger", "mood"] as const) {
    expect(ticking.stats[key]).toBeCloseTo(offline.stats[key]);
  }
});
