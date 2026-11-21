/** A completed start/end pair keeps only its duration. Open pairs need an ID until they close. */
export type TaskTimingSample = number | { id: string; startMs: number };

const WINDOW = 128;
const MINIMUM_AT_RISK = 8;

export function observeTiming(
  history: TaskTimingSample[], id: string, status: "running" | "completed" | "failed", timeMs: number
): TaskTimingSample[] {
  if (!id || !Number.isFinite(timeMs)) return history;
  const index = history.findIndex(sample => typeof sample !== "number" && sample.id === id);
  if (status === "running") {
    return index < 0 ? [...history, { id, startMs: timeMs }].slice(-WINDOW) : history;
  }
  const start = history[index];
  if (!start || typeof start === "number") return history;
  const duration = timeMs - start.startMs;
  if (duration < 0) return history.filter((_, i) => i !== index);
  return history.map((sample, i) => i === index ? duration : sample);
}

export function restoreTiming(raw: unknown): TaskTimingSample[] {
  if (!Array.isArray(raw)) return [];
  return raw.slice(-WINDOW).filter((sample): sample is TaskTimingSample =>
    typeof sample === "number" ? Number.isFinite(sample) && sample >= 0 :
      sample !== null && typeof sample === "object" && typeof sample.id === "string" &&
      Number.isFinite(sample.startMs)
  ).map(sample => typeof sample === "number" ? sample : { id: sample.id, startMs: sample.startMs });
}

export function observedStart(history: TaskTimingSample[], id: string): number | undefined {
  const target = history.find(sample => typeof sample !== "number" && sample.id === id);
  return typeof target === "object" ? target.startMs : undefined;
}

export interface RemainingTime {
  atRisk: number;
  medianMs: number;
  p80Ms: number | null;
}

/** Conditional Kaplan–Meier quantiles, evaluated only beyond the target's current age. */
export function remainingTime(history: TaskTimingSample[], id: string, nowMs: number): RemainingTime | null {
  const start = observedStart(history, id);
  if (start === undefined || !Number.isFinite(nowMs) || nowMs < start) return null;
  const elapsed = nowMs - start;
  const byAge = new Map<number, { exits: number; endings: number }>();
  let atRisk = 0;
  for (const sample of history) {
    if (typeof sample !== "number" && sample.id === id) continue;
    const ended = typeof sample === "number";
    const age = ended ? sample : nowMs - sample.startMs;
    if (age <= elapsed) continue;
    const bucket = byAge.get(age) ?? { exits: 0, endings: 0 };
    bucket.exits++;
    if (ended) bucket.endings++;
    byAge.set(age, bucket);
    atRisk++;
  }
  if (atRisk < MINIMUM_AT_RISK) return null;
  let remaining = atRisk;
  let survival = 1;
  let medianMs: number | null = null;
  let p80Ms: number | null = null;
  for (const [age, bucket] of [...byAge].sort(([a], [b]) => a - b)) {
    // Censored peers leave the risk set after observed endings at the same age.
    survival *= (remaining - bucket.endings) / remaining;
    remaining -= bucket.exits;
    if (medianMs === null && survival <= 0.5 + Number.EPSILON) medianMs = age - elapsed;
    if (survival <= 0.2 + Number.EPSILON) { p80Ms = age - elapsed; break; }
  }
  return medianMs === null ? null : { atRisk, medianMs, p80Ms };
}
