import { readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { observeTiming, remainingTime, type TaskTimingSample } from "../src/shared/task-timing.js";

interface Run { id: string; start: number; end: number }
interface Event { time: number; kind: "start" | "end" | "estimate"; run: Run }

function replay(runs: Run[], age: number) {
  const ordered = [...runs].sort((a, b) => a.start - b.start || a.id.localeCompare(b.id));
  const holdoutStart = ordered[Math.floor(ordered.length / 4)]!.start;
  const events: Event[] = [];
  for (const run of runs) {
    events.push({ time: run.start, kind: "start", run }, { time: run.end, kind: "end", run });
    if (run.start >= holdoutStart && run.end > run.start + age) {
      events.push({ time: run.start + age, kind: "estimate", run });
    }
  }
  const priority = { start: 0, end: 1, estimate: 2 };
  events.sort((a, b) => a.time - b.time || priority[a.kind] - priority[b.kind] || a.run.id.localeCompare(b.run.id));
  let history: TaskTimingSample[] = [];
  let eligible = 0, issued = 0, upperIssued = 0, upperCovered = 0;
  let conditionalError = 0, naiveError = 0, completedOnlyError = 0;
  const lowerMedian = (values: number[]) => values[Math.ceil(values.length / 2) - 1]!;
  for (const event of events) {
    if (event.kind !== "estimate") {
      history = observeTiming(history, event.run.id, event.kind === "start" ? "running" : "completed", event.time);
      continue;
    }
    eligible++;
    const forecast = remainingTime(history, event.run.id, event.time);
    if (!forecast) continue;
    const completed = history.filter((v): v is number => typeof v === "number").sort((a, b) => a - b);
    const survivors = completed.filter(v => v > age);
    const remaining = event.run.end - event.time;
    expect(survivors.length).toBeGreaterThan(0);
    issued++;
    conditionalError += Math.abs(forecast.medianMs - remaining);
    naiveError += Math.abs(Math.max(0, lowerMedian(completed) - age) - remaining);
    completedOnlyError += Math.abs(lowerMedian(survivors) - age - remaining);
    if (forecast.p80Ms !== null) {
      upperIssued++;
      if (remaining <= forecast.p80Ms) upperCovered++;
    }
  }
  const seconds = (sum: number) => issued ? Math.round(sum / issued / 100) / 10 : null;
  return { eligible, issued, forecastMaeSeconds: seconds(conditionalError), baselineMaeSeconds: seconds(naiveError),
    completedOnlyMaeSeconds: seconds(completedOnlyError), upperCovered, upperIssued };
}

it("replays dated public runs, with a chronological warm-up and paired baselines", () => {
  const local: {id: number; run_attempt: number; run_started_at: string; updated_at: string}[] =
    JSON.parse(readFileSync("tests/fixtures/public-workflow-runs.json", "utf8"));
  const own = local.map(row => ({
    id: `${row.id}/${row.run_attempt}`, start: Date.parse(row.run_started_at), end: Date.parse(row.updated_at)
  }));
  const cli = readFileSync("tests/fixtures/cli-trunk-timing.csv", "utf8").trim().split("\n").slice(1).map(line => {
    const [id, attempt, start, end] = line.split(",");
    return { id: `${id}/${attempt}`, start: Date.parse(start!), end: Date.parse(end!) };
  });
  for (const [dataset, runs] of [["Sidekin", own], ["cli/cli", cli]] as const) {
    expect(runs.every(r => Number.isFinite(r.start) && r.end >= r.start)).toBe(true);
    for (const seconds of [60, 180, 300, 420, 600]) {
      const result = replay(runs, seconds * 1000);
      console.log(dataset, seconds, JSON.stringify(result));
      if (result.eligible === 0) expect(result.issued).toBe(0);
      expect(result.issued).toBeLessThanOrEqual(result.eligible);
      expect(result.upperCovered).toBeLessThanOrEqual(result.upperIssued);
      if (dataset === "cli/cli" && seconds === 600) {
        expect(result).toEqual({ eligible: 54, issued: 53, forecastMaeSeconds: 47.8,
          baselineMaeSeconds: 61.1, completedOnlyMaeSeconds: 47.9, upperCovered: 39, upperIssued: 53 });
      }
      if (dataset === "Sidekin" && seconds === 180) expect([result.eligible, result.issued]).toEqual([8, 0]);
    }
  }
});
