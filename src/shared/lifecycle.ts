import type {
  ActivityFeedItem,
  AgentActivity,
  AgentProvider,
  CareAction,
  CareAvailability,
  GrowthJournalEntry,
  PetMotion,
  PetSnapshot,
  PetStage,
  PetTemperament
} from "./types.js";

const MAXIMUM_OFFLINE_INTERVAL_MS = 12 * 60 * 60 * 1_000;
export const RUNNING_STALE_AFTER_MS = 2 * 60 * 60 * 1_000;
export const STAGE_THRESHOLDS: Record<PetStage, number> = {
  egg: 0,
  hatchling: 30,
  juvenile: 120,
  ascended: 300,
  legendary: 600
};
const STAGE_RANK: Record<PetStage, number> = {
  egg: 0,
  hatchling: 1,
  juvenile: 2,
  ascended: 3,
  legendary: 4
};
const CARE_COOLDOWNS: Record<CareAction, number> = {
  feed: 10 * 60 * 1_000,
  play: 12 * 60 * 1_000,
  sleepOrWake: 30 * 60 * 1_000
};

function iso(now = new Date()): string { return now.toISOString(); }
function day(now: Date): string { return now.toISOString().slice(0, 10); }
function clamp(value: number): number { return Math.min(100, Math.max(0, value)); }

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function finiteNumber(value: unknown, fallback: number, minimum = 0, maximum = 1_000_000_000): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(maximum, Math.max(minimum, value))
    : fallback;
}

function finiteInteger(value: unknown, fallback: number, maximum = 1_000_000_000): number {
  return Math.round(finiteNumber(value, fallback, 0, maximum));
}

function safeText(value: unknown, fallback: string, maximum: number): string {
  if (typeof value !== "string") return fallback;
  const cleaned = value.replaceAll(/\p{Cc}/gu, " ").trim().slice(0, maximum);
  return cleaned || fallback;
}

function safeOptionalText(value: unknown, maximum: number): string | undefined {
  const cleaned = safeText(value, "", maximum);
  return cleaned || undefined;
}

function safeDate(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed.toISOString() : fallback;
}

function safeIdentifierText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const cleaned = value.trim();
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/.test(cleaned) ? cleaned : undefined;
}

function clampStats(snapshot: PetSnapshot): void {
  snapshot.stats.hunger = clamp(snapshot.stats.hunger);
  snapshot.stats.mood = clamp(snapshot.stats.mood);
  snapshot.stats.energy = clamp(snapshot.stats.energy);
}

function appendJournal(snapshot: PetSnapshot, entry: Omit<GrowthJournalEntry, "id">): void {
  const id = `${entry.timestamp}:${entry.type}:${snapshot.growthJournal.length}`;
  snapshot.growthJournal = [...snapshot.growthJournal, { id, ...entry }].slice(-100);
}

function recalculateStage(snapshot: PetSnapshot, now = new Date()): void {
  const previous = snapshot.stage;
  const earned: PetStage = snapshot.experience < STAGE_THRESHOLDS.hatchling
    ? "egg"
    : snapshot.experience < STAGE_THRESHOLDS.juvenile
      ? "hatchling"
      : snapshot.experience < STAGE_THRESHOLDS.ascended
        ? "juvenile"
        : snapshot.experience < STAGE_THRESHOLDS.legendary
          ? "ascended"
          : "legendary";
  if (STAGE_RANK[earned] > STAGE_RANK[snapshot.stage]) snapshot.stage = earned;
  if (snapshot.stage !== previous) appendJournal(snapshot, {
    type: "evolution",
    title: `Evolved into ${snapshot.stage}`,
    detail: `Reached ${snapshot.experience} XP while keeping the same lineage identity.`,
    timestamp: iso(now)
  });
}

function streakFor(days: string[], now = new Date()): number {
  if (!days.length) return 0;
  const unique = [...new Set(days)].sort().reverse();
  const today = new Date(`${day(now)}T00:00:00Z`);
  const latest = new Date(`${unique[0]}T00:00:00Z`);
  const latestGap = (today.getTime() - latest.getTime()) / 86_400_000;
  if (latestGap < 0 || latestGap > 1) return 0;
  let streak = 1;
  let previous = latest;
  for (const value of unique.slice(1)) {
    const current = new Date(`${value}T00:00:00Z`);
    if (previous.getTime() - current.getTime() !== 86_400_000) break;
    streak += 1;
    previous = current;
  }
  return streak;
}

export function temperamentFor(snapshot: PetSnapshot): PetTemperament {
  if (snapshot.completedTasks >= snapshot.feedCount + snapshot.playCount && snapshot.completedTasks >= 3) return "focused";
  if (snapshot.sparkAffinity > snapshot.careAffinity * 1.15) return "playful";
  return "steady";
}

export function makeDefaultSnapshot(now = new Date()): PetSnapshot {
  const timestamp = iso(now);
  return {
    schemaVersion: 6,
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
    careAffinity: 0,
    sparkAffinity: 0,
    feedCount: 0,
    playCount: 0,
    restCount: 0,
    completedTasks: 0,
    failedTasks: 0,
    processedAgentSignals: [],
    lastAgentSignalAt: null,
    lastAgentSignalActivity: null,
    lastCareAt: {},
    activeTaskDays: [],
    currentStreak: 0,
    growthJournal: [],
    activityFeed: []
  };
}

export function migrateSnapshot(raw: unknown, now = new Date()): PetSnapshot {
  const base = makeDefaultSnapshot(now);
  const current = isRecord(raw) ? raw : {};
  const legacyStage = typeof current.stage === "string" ? current.stage : undefined;
  const stage = legacyStage === "guardian" || legacyStage === "dreamer"
    ? "ascended"
    : legacyStage && legacyStage in STAGE_RANK
      ? legacyStage as PetStage
      : base.stage;
  const legacyWardrobe = isRecord(current.wardrobe) ? current.wardrobe : {};
  const stats = isRecord(current.stats) ? current.stats : {};
  const createdAt = safeDate(current.createdAt, base.createdAt);
  const lastUpdatedAt = safeDate(current.lastUpdatedAt, base.lastUpdatedAt);
  const activityChangedAt = safeDate(current.activityChangedAt, lastUpdatedAt);
  const processedSource = Array.isArray(current.processedAgentSignals)
    ? current.processedAgentSignals
    : Array.isArray(current.processedCodexSignals)
      ? current.processedCodexSignals
      : [];
  const processedAgentSignals = processedSource
    .map((value) => safeOptionalText(value, 256))
    .filter((value): value is string => Boolean(value))
    .slice(-128);
  const lastAgentSignalAtSource = current.lastAgentSignalAt ?? current.lastCodexSignalAt;
  const lastAgentSignalAt = lastAgentSignalAtSource === null
    ? null
    : typeof lastAgentSignalAtSource === "string"
      ? safeDate(lastAgentSignalAtSource, lastUpdatedAt)
      : null;
  const lastAgentActivitySource = current.lastAgentSignalActivity ?? current.lastCodexSignalActivity;
  const lastAgentSignalActivity = ["idle", "running", "completed", "failed"].includes(String(lastAgentActivitySource))
    ? lastAgentActivitySource as AgentActivity
    : null;
  const careSource = isRecord(current.lastCareAt) ? current.lastCareAt : {};
  const lastCareAt: Partial<Record<CareAction, string>> = {};
  for (const action of ["feed", "play", "sleepOrWake"] as const) {
    if (typeof careSource[action] === "string") lastCareAt[action] = safeDate(careSource[action], lastUpdatedAt);
  }
  const activeTaskDays = (Array.isArray(current.activeTaskDays) ? current.activeTaskDays : [])
    .filter((value): value is string => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(new Date(`${value}T00:00:00Z`).getTime()))
    .filter((value, index, values) => values.indexOf(value) === index)
    .sort()
    .slice(-90);
  const growthJournal = (Array.isArray(current.growthJournal) ? current.growthJournal : []).flatMap((value, index): GrowthJournalEntry[] => {
    if (!isRecord(value) || !["care", "task", "evolution", "milestone"].includes(String(value.type))) return [];
    const timestamp = safeDate(value.timestamp, lastUpdatedAt);
    return [{
      id: safeText(value.id, `${timestamp}:recovered:${index}`, 256),
      type: value.type as GrowthJournalEntry["type"],
      title: safeText(value.title, "Recovered journal entry", 160),
      detail: safeText(value.detail, "Local Sidekin activity.", 600),
      timestamp
    }];
  }).slice(-100);
  const activityFeed = (Array.isArray(current.activityFeed) ? current.activityFeed : []).flatMap((value, index): ActivityFeedItem[] => {
    if (!isRecord(value) || !["running", "completed", "failed", "interrupted"].includes(String(value.status))) return [];
    const provider: AgentProvider = value.provider === "claude" ? "claude" : "codex";
    const startedAt = safeDate(value.startedAt, lastUpdatedAt);
    const updatedAt = safeDate(value.updatedAt, startedAt);
    const durationMs = typeof value.durationMs === "number" && Number.isFinite(value.durationMs)
      ? Math.max(0, Math.min(value.durationMs, 365 * 24 * 60 * 60 * 1_000))
      : undefined;
    return [{
      id: safeText(value.id, `${provider}:recovered-${index}`, 256),
      title: safeText(value.title, `${provider === "claude" ? "Claude Code" : "Codex"} task`, 160),
      project: safeText(value.project, "Local workspace", 120),
      status: value.status as ActivityFeedItem["status"],
      provider,
      sessionID: safeOptionalText(value.sessionID, 160),
      startedAt,
      updatedAt,
      durationMs
    }];
  }).slice(-8);
  const customTemplateID = legacyWardrobe.customTemplateID === null
    ? null
    : safeIdentifierText(legacyWardrobe.customTemplateID) ?? base.wardrobe.customTemplateID;
  const migrated: PetSnapshot = {
    schemaVersion: 6,
    name: safeText(current.name, base.name, 64),
    createdAt,
    lastUpdatedAt,
    activityChangedAt,
    stats: {
      hunger: finiteNumber(stats.hunger, base.stats.hunger, 0, 100),
      mood: finiteNumber(stats.mood, base.stats.mood, 0, 100),
      energy: finiteNumber(stats.energy, base.stats.energy, 0, 100)
    },
    experience: finiteInteger(current.experience, base.experience),
    stage,
    isSleeping: typeof current.isSleeping === "boolean" ? current.isSleeping : base.isSleeping,
    codexActivity: ["idle", "running", "completed", "failed"].includes(String(current.codexActivity))
      ? current.codexActivity as PetSnapshot["codexActivity"]
      : base.codexActivity,
    wardrobe: {
      theme: safeIdentifierText(legacyWardrobe.theme) ?? base.wardrobe.theme,
      customTemplateID
    },
    careAffinity: finiteInteger(current.careAffinity, base.careAffinity),
    sparkAffinity: finiteInteger(current.sparkAffinity, base.sparkAffinity),
    feedCount: finiteInteger(current.feedCount, base.feedCount),
    playCount: finiteInteger(current.playCount, base.playCount),
    restCount: finiteInteger(current.restCount, base.restCount),
    completedTasks: finiteInteger(current.completedTasks, base.completedTasks),
    failedTasks: finiteInteger(current.failedTasks, base.failedTasks),
    processedAgentSignals,
    lastAgentSignalAt,
    lastAgentSignalActivity,
    lastCareAt,
    activeTaskDays,
    currentStreak: streakFor(activeTaskDays, now),
    growthJournal,
    activityFeed
  };
  clampStats(migrated);
  return migrated;
}

export function careAvailability(snapshot: PetSnapshot, now = new Date()): Record<CareAction, CareAvailability> {
  const availability = (action: CareAction, condition = true, reason?: string): CareAvailability => {
    if (!condition) return { available: false, reason };
    const last = snapshot.lastCareAt[action] ? new Date(snapshot.lastCareAt[action]!).getTime() : 0;
    const next = last + CARE_COOLDOWNS[action];
    if (last && next > now.getTime()) return { available: false, reason: "Let this care action settle first.", nextAvailableAt: iso(new Date(next)) };
    return { available: true };
  };
  return {
    feed: availability("feed", snapshot.stats.hunger < 92, "Already comfortably full."),
    play: availability("play", !snapshot.isSleeping && snapshot.stats.energy >= 16, snapshot.isSleeping ? "Wake your Sidekin before playing." : "Too tired to play."),
    sleepOrWake: snapshot.isSleeping
      ? { available: true }
      : availability("sleepOrWake", snapshot.stats.energy < 90, "Already well rested.")
  };
}

function reconcileStaleActivity(snapshot: PetSnapshot, now: Date): void {
  let interrupted = 0;
  snapshot.activityFeed = snapshot.activityFeed.map((item) => {
    if (item.status !== "running" || now.getTime() - new Date(item.updatedAt).getTime() <= RUNNING_STALE_AFTER_MS) return item;
    interrupted += 1;
    return { ...item, status: "interrupted", updatedAt: iso(now), durationMs: Math.max(0, now.getTime() - new Date(item.startedAt).getTime()) };
  });
  if (interrupted && !snapshot.activityFeed.some((item) => item.status === "running")) {
    snapshot.codexActivity = "idle";
    snapshot.activityChangedAt = iso(now);
    appendJournal(snapshot, { type: "task", title: "Recovered stale activity", detail: `${interrupted} task ${interrupted === 1 ? "card was" : "cards were"} marked interrupted after losing lifecycle contact.`, timestamp: iso(now) });
  }
}

export function clearInterruptedTasks(snapshot: PetSnapshot, now = new Date()): PetSnapshot {
  const result = structuredClone(snapshot);
  result.activityFeed = result.activityFeed.filter((item) => item.status !== "interrupted");
  result.lastUpdatedAt = iso(now);
  return result;
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
  reconcileStaleActivity(result, now);
  result.currentStreak = streakFor(result.activeTaskDays, now);
  result.lastUpdatedAt = iso(now);
  if (["completed", "failed"].includes(result.codexActivity) && now.getTime() - new Date(result.activityChangedAt).getTime() > 12_000) {
    result.codexActivity = result.activityFeed.some((item) => item.status === "running") ? "running" : "idle";
    result.activityChangedAt = iso(now);
  }
  recalculateStage(result, now);
  return result;
}

export function performCare(snapshot: PetSnapshot, action: CareAction, now = new Date()): { snapshot: PetSnapshot; motion: PetMotion; rewarded: boolean; message: string } {
  const result = advance(snapshot, now);
  const available = careAvailability(result, now)[action];
  if (!available.available) return { snapshot: result, motion: motionFor(result), rewarded: false, message: available.reason ?? "Not ready yet." };
  result.lastCareAt[action] = iso(now);
  let motion: PetMotion;
  let xp = 0;
  let message = "";
  if (action === "feed") {
    result.isSleeping = false;
    result.stats.hunger += 28;
    result.stats.mood += 5;
    result.stats.energy += 2;
    xp = 5;
    result.careAffinity += 3;
    result.feedCount += 1;
    motion = "feed";
    message = "Fed and cared for.";
  } else if (action === "play") {
    result.stats.mood += 25;
    result.stats.energy -= 8;
    result.stats.hunger -= 4;
    xp = 7;
    result.sparkAffinity += 4;
    result.playCount += 1;
    motion = "play";
    message = "Playtime strengthened your bond.";
  } else if (result.isSleeping) {
    result.isSleeping = false;
    result.stats.mood += 2;
    motion = "wake";
    message = "Awake and ready.";
  } else {
    result.isSleeping = true;
    result.stats.energy += 18;
    result.stats.hunger -= 3;
    xp = result.stats.energy < 70 ? 3 : 1;
    result.careAffinity += 1;
    result.restCount += 1;
    motion = "sleep";
    message = "Settled in for restorative sleep.";
  }
  result.experience += xp;
  appendJournal(result, { type: "care", title: message, detail: xp ? `Earned ${xp} XP through meaningful care.` : "Care state updated.", timestamp: iso(now) });
  clampStats(result);
  result.lastUpdatedAt = iso(now);
  recalculateStage(result, now);
  return { snapshot: result, motion, rewarded: true, message };
}

function upsertFeed(items: ActivityFeedItem[], activity: AgentActivity, provider: AgentProvider, sessionID: string | undefined, eventID: string | undefined, title: string | undefined, project: string | undefined, now: Date): ActivityFeedItem[] {
  if (activity === "idle") return items;
  const rawID = eventID || sessionID || `sidekin-${now.getTime()}`;
  const id = `${provider}:${rawID}`;
  const index = items.findIndex((item) => item.id === id);
  const current = index >= 0 ? items[index]! : undefined;
  const startedAt = current?.startedAt ?? iso(now);
  const next: ActivityFeedItem = {
    id,
    title: safeText(title, current?.title || `${provider === "claude" ? "Claude Code" : "Codex"} task`, 160),
    project: safeText(project, current?.project || "Local workspace", 120),
    provider,
    sessionID: safeOptionalText(sessionID, 160),
    status: activity,
    startedAt,
    updatedAt: iso(now),
    durationMs: activity === "running" ? undefined : Math.max(0, now.getTime() - new Date(startedAt).getTime())
  };
  const result = index >= 0 ? items.filter((_, itemIndex) => itemIndex !== index) : [...items];
  result.push(next);
  return result.slice(-8);
}

function aggregateActivity(items: ActivityFeedItem[], fallback: AgentActivity): AgentActivity {
  return items.some((item) => item.status === "running") ? "running" : fallback;
}

export function applyActivity(snapshot: PetSnapshot, activity: AgentActivity, options: {
  now?: Date;
  provider?: AgentProvider;
  sessionID?: string;
  eventID?: string;
  title?: string;
  project?: string;
  deduplicate?: boolean;
} = {}): { snapshot: PetSnapshot; applied: boolean; motion: PetMotion } {
  const now = options.now ?? new Date();
  const provider = options.provider ?? "codex";
  const identity = safeOptionalText(options.eventID, 160);
  const sessionID = safeOptionalText(options.sessionID, 160);
  const signalKey = identity ? `${provider}:${identity}:${activity}` : undefined;
  if (options.deduplicate !== false) {
    if (signalKey && snapshot.processedAgentSignals.includes(signalKey)) return { snapshot, applied: false, motion: motionFor(snapshot) };
    if (!signalKey && snapshot.lastAgentSignalAt) {
      const previous = new Date(snapshot.lastAgentSignalAt);
      if (now < previous) return { snapshot, applied: false, motion: motionFor(snapshot) };
      if (snapshot.lastAgentSignalActivity === activity && now.getTime() - previous.getTime() < 5_000) return { snapshot, applied: false, motion: motionFor(snapshot) };
    }
  }

  const effective = new Date(Math.max(now.getTime(), new Date(snapshot.lastUpdatedAt).getTime()));
  const result = advance(snapshot, effective);
  result.lastAgentSignalAt = iso(now);
  result.lastAgentSignalActivity = activity;
  if (signalKey) result.processedAgentSignals = [...result.processedAgentSignals, signalKey].slice(-128);
  result.activityChangedAt = iso(effective);
  result.activityFeed = upsertFeed(result.activityFeed, activity, provider, sessionID, identity, options.title, options.project, now);
  result.codexActivity = aggregateActivity(result.activityFeed, activity);

  if (activity === "running") {
    result.isSleeping = false;
    result.stats.energy -= 1;
    result.stats.hunger -= 0.5;
  } else if (activity === "completed") {
    result.isSleeping = false;
    result.experience += 18;
    result.stats.mood += 10;
    result.stats.energy -= 2;
    result.careAffinity += 4;
    result.completedTasks += 1;
    result.activeTaskDays = [...new Set([...result.activeTaskDays, day(now)])].sort().slice(-90);
    result.currentStreak = streakFor(result.activeTaskDays, now);
    appendJournal(result, { type: "task", title: `${provider === "claude" ? "Claude Code" : "Codex"} task completed`, detail: `Earned 18 XP. Current focus streak: ${result.currentStreak} day${result.currentStreak === 1 ? "" : "s"}.`, timestamp: iso(now) });
  } else if (activity === "failed") {
    result.isSleeping = false;
    result.experience += 4;
    result.stats.mood -= 3;
    result.stats.energy -= 3;
    result.careAffinity += 1;
    result.failedTasks += 1;
    appendJournal(result, { type: "task", title: `${provider === "claude" ? "Claude Code" : "Codex"} task needs attention`, detail: "A failed task still grants a small amount of growth without punishing the companion.", timestamp: iso(now) });
  }
  clampStats(result);
  result.lastUpdatedAt = iso(effective);
  recalculateStage(result, effective);
  return { snapshot: result, applied: true, motion: motionFor(result) };
}

export function motionFor(snapshot: PetSnapshot): PetMotion {
  if (snapshot.isSleeping) return "sleep";
  if (snapshot.codexActivity === "running") return snapshot.experience % 2 === 0 ? "working-scan" : "working-run";
  if (snapshot.codexActivity === "completed") return "celebrate";
  if (snapshot.codexActivity === "failed") return "fail";
  const cycle = Math.floor(Date.now() / 9_000) % 4;
  const motions: PetMotion[] = temperamentFor(snapshot) === "playful"
    ? ["idle-hop", "idle-look", "idle-stretch", "idle-hop"]
    : temperamentFor(snapshot) === "focused"
      ? ["idle-look", "idle-float", "idle-look", "idle-stretch"]
      : ["idle-float", "idle-look", "idle-stretch", "idle-hop"];
  return motions[cycle]!;
}

export function stageProgress(snapshot: Pick<PetSnapshot, "stage" | "experience">): number {
  const rank = STAGE_RANK[snapshot.stage];
  if (rank >= STAGE_RANK.legendary) return 1;
  const stages = Object.keys(STAGE_RANK).sort((a, b) => STAGE_RANK[a as PetStage] - STAGE_RANK[b as PetStage]) as PetStage[];
  const start = STAGE_THRESHOLDS[snapshot.stage];
  const end = STAGE_THRESHOLDS[stages[rank + 1]!];
  return Math.min(1, Math.max(0, (snapshot.experience - start) / (end - start)));
}
