import type {
  ActivityFeedItem,
  CareAction,
  CodexActivity,
  PetMotion,
  PetSnapshot,
  PetStage
} from "./types.js";

const MAXIMUM_OFFLINE_INTERVAL_MS = 12 * 60 * 60 * 1_000;
const STAGE_RANK: Record<PetStage, number> = {
  egg: 0,
  hatchling: 1,
  juvenile: 2,
  ascended: 3,
  legendary: 4
};

function iso(now = new Date()): string {
  return now.toISOString();
}

function clamp(value: number): number {
  return Math.min(100, Math.max(0, value));
}

function clampStats(snapshot: PetSnapshot): void {
  snapshot.stats.hunger = clamp(snapshot.stats.hunger);
  snapshot.stats.mood = clamp(snapshot.stats.mood);
  snapshot.stats.energy = clamp(snapshot.stats.energy);
}

function recalculateStage(snapshot: PetSnapshot): void {
  const earned: PetStage = snapshot.experience < 20
    ? "egg"
    : snapshot.experience < 75
      ? "hatchling"
      : snapshot.experience < 180
        ? "juvenile"
        : snapshot.experience < 360
          ? "ascended"
          : "legendary";
  if (STAGE_RANK[earned] > STAGE_RANK[snapshot.stage]) snapshot.stage = earned;
}

export function makeDefaultSnapshot(now = new Date()): PetSnapshot {
  const timestamp = iso(now);
  return {
    schemaVersion: 4,
    name: "Sprout",
    createdAt: timestamp,
    lastUpdatedAt: timestamp,
    activityChangedAt: timestamp,
    stats: { hunger: 76, mood: 82, energy: 78 },
    experience: 0,
    stage: "egg",
    isSleeping: false,
    codexActivity: "idle",
    wardrobe: { theme: "nova", customTemplateID: null },
    cosmetics: { hat: "none", face: "none", aura: "none" },
    careAffinity: 0,
    sparkAffinity: 0,
    feedCount: 0,
    playCount: 0,
    restCount: 0,
    completedTasks: 0,
    failedTasks: 0,
    processedCodexSignals: [],
    lastCodexSignalAt: null,
    lastCodexSignalActivity: null,
    activityFeed: []
  };
}

export function migrateSnapshot(raw: Partial<PetSnapshot>, now = new Date()): PetSnapshot {
  const base = makeDefaultSnapshot(now);
  const legacyStage = raw.stage as string | undefined;
  const stage = legacyStage === "guardian" || legacyStage === "dreamer"
    ? "ascended"
    : legacyStage && legacyStage in STAGE_RANK
      ? legacyStage as PetStage
      : base.stage;
  return {
    ...base,
    ...raw,
    schemaVersion: 4,
    stage,
    stats: { ...base.stats, ...(raw.stats ?? {}) },
    wardrobe: { ...base.wardrobe, ...(raw.wardrobe ?? {}) },
    cosmetics: { ...base.cosmetics, ...(raw.cosmetics ?? {}) },
    processedCodexSignals: raw.processedCodexSignals ?? [],
    activityFeed: raw.activityFeed ?? []
  };
}

export function advance(snapshot: PetSnapshot, now = new Date()): PetSnapshot {
  const result = structuredClone(snapshot);
  const last = new Date(result.lastUpdatedAt).getTime();
  const rawInterval = now.getTime() - last;
  if (!Number.isFinite(rawInterval) || rawInterval <= 0) return result;

  const hours = Math.min(rawInterval, MAXIMUM_OFFLINE_INTERVAL_MS) / 3_600_000;
  if (result.isSleeping) {
    result.stats.hunger -= hours * 2;
    result.stats.mood += hours;
    result.stats.energy += hours * 18;
    if (result.stats.energy >= 99) result.isSleeping = false;
  } else {
    result.stats.hunger -= hours * 4;
    result.stats.mood -= hours * 1.3;
    result.stats.energy -= hours * 2.2;
  }
  clampStats(result);
  result.lastUpdatedAt = iso(now);
  if (["completed", "failed"].includes(result.codexActivity)) {
    if (now.getTime() - new Date(result.activityChangedAt).getTime() > 12_000) {
      result.codexActivity = "idle";
      result.activityChangedAt = iso(now);
    }
  }
  recalculateStage(result);
  return result;
}

export function performCare(
  snapshot: PetSnapshot,
  action: CareAction,
  now = new Date()
): { snapshot: PetSnapshot; motion: PetMotion } {
  const result = advance(snapshot, now);
  let motion: PetMotion;
  if (action === "feed") {
    result.isSleeping = false;
    result.stats.hunger += 28;
    result.stats.mood += 5;
    result.stats.energy += 2;
    result.experience += 7;
    result.careAffinity += 3;
    result.feedCount += 1;
    motion = "feed";
  } else if (action === "play") {
    result.isSleeping = false;
    result.stats.mood += 25;
    result.stats.energy -= 8;
    result.stats.hunger -= 4;
    result.experience += 9;
    result.sparkAffinity += 4;
    result.playCount += 1;
    motion = "play";
  } else if (result.isSleeping) {
    result.isSleeping = false;
    result.stats.mood += 2;
    motion = "wake";
  } else {
    result.isSleeping = true;
    result.stats.energy += 18;
    result.stats.hunger -= 3;
    result.experience += 4;
    result.careAffinity += 1;
    result.restCount += 1;
    motion = "sleep";
  }
  clampStats(result);
  result.lastUpdatedAt = iso(now);
  recalculateStage(result);
  return { snapshot: result, motion };
}

function upsertFeed(
  items: ActivityFeedItem[],
  activity: CodexActivity,
  eventID: string | undefined,
  title: string | undefined,
  project: string | undefined,
  now: Date
): ActivityFeedItem[] {
  if (activity === "idle") return items;
  const id = eventID || `sidekin-${now.getTime()}`;
  const index = items.findIndex((item) => item.id === id);
  const current = index >= 0 ? items[index]! : undefined;
  const startedAt = current?.startedAt ?? iso(now);
  const next: ActivityFeedItem = {
    id,
    title: title?.trim() || current?.title || "Codex task",
    project: project?.trim() || current?.project || "Local workspace",
    status: activity,
    startedAt,
    updatedAt: iso(now),
    durationMs: activity === "running" ? undefined : Math.max(0, now.getTime() - new Date(startedAt).getTime())
  };
  const result = index >= 0 ? items.filter((_, itemIndex) => itemIndex !== index) : [...items];
  result.push(next);
  return result.slice(-5);
}

function aggregateActivity(items: ActivityFeedItem[], fallback: CodexActivity): CodexActivity {
  if (items.some((item) => item.status === "running")) return "running";
  return fallback;
}

export function applyActivity(
  snapshot: PetSnapshot,
  activity: CodexActivity,
  options: {
    now?: Date;
    eventID?: string;
    title?: string;
    project?: string;
    deduplicate?: boolean;
  } = {}
): { snapshot: PetSnapshot; applied: boolean; motion: PetMotion } {
  const now = options.now ?? new Date();
  const signalKey = options.eventID ? `${activity}:${options.eventID}` : undefined;
  if (options.deduplicate !== false) {
    if (signalKey && snapshot.processedCodexSignals.includes(signalKey)) {
      return { snapshot, applied: false, motion: motionFor(snapshot) };
    }
    if (!signalKey && snapshot.lastCodexSignalAt) {
      const previous = new Date(snapshot.lastCodexSignalAt);
      if (now < previous) return { snapshot, applied: false, motion: motionFor(snapshot) };
      if (snapshot.lastCodexSignalActivity === activity && now.getTime() - previous.getTime() < 5_000) {
        return { snapshot, applied: false, motion: motionFor(snapshot) };
      }
    }
  }

  const effective = new Date(Math.max(now.getTime(), new Date(snapshot.lastUpdatedAt).getTime()));
  const result = advance(snapshot, effective);
  result.lastCodexSignalAt = iso(now);
  result.lastCodexSignalActivity = activity;
  if (signalKey) result.processedCodexSignals = [...result.processedCodexSignals, signalKey].slice(-64);
  result.activityChangedAt = iso(effective);
  result.activityFeed = upsertFeed(
    result.activityFeed,
    activity,
    options.eventID,
    options.title,
    options.project,
    now
  );
  result.codexActivity = aggregateActivity(result.activityFeed, activity);

  if (activity === "running") {
    result.isSleeping = false;
    result.stats.energy -= 1;
    result.stats.hunger -= 0.5;
  } else if (activity === "completed") {
    result.isSleeping = false;
    result.experience += 15;
    result.stats.mood += 10;
    result.stats.energy -= 2;
    result.careAffinity += 4;
    result.completedTasks += 1;
  } else if (activity === "failed") {
    result.isSleeping = false;
    result.experience += 4;
    result.stats.mood -= 4;
    result.stats.energy -= 3;
    result.careAffinity += 1;
    result.failedTasks += 1;
  }
  clampStats(result);
  result.lastUpdatedAt = iso(effective);
  recalculateStage(result);
  return { snapshot: result, applied: true, motion: motionFor(result) };
}

export function motionFor(snapshot: PetSnapshot): PetMotion {
  if (snapshot.isSleeping) return "sleep";
  if (snapshot.codexActivity === "running") {
    return snapshot.experience % 2 === 0 ? "working-scan" : "working-run";
  }
  if (snapshot.codexActivity === "completed") return "celebrate";
  if (snapshot.codexActivity === "failed") return "fail";
  const cycle = Math.floor(Date.now() / 9_000) % 4;
  return (["idle-float", "idle-look", "idle-stretch", "idle-hop"] as PetMotion[])[cycle]!;
}

export function stageProgress(snapshot: PetSnapshot): number {
  if (snapshot.stage === "egg") return Math.min(1, snapshot.experience / 20);
  if (snapshot.stage === "hatchling") return Math.min(1, Math.max(0, (snapshot.experience - 20) / 55));
  if (snapshot.stage === "juvenile") return Math.min(1, Math.max(0, (snapshot.experience - 75) / 105));
  if (snapshot.stage === "ascended") return Math.min(1, Math.max(0, (snapshot.experience - 180) / 180));
  return 1;
}
