# How much longer will this task run?

Sidekin's command center estimates the time left on an active task from task signals on the current device. A job that has already run for ten minutes belongs to a different comparison group from a job that has just started. The elapsed clock keeps working when a forecast has too little support.

## What the estimate uses

The local save retains up to 128 observed starts in insertion order. Each open task contributes its ID and start time. Once a matching terminal signal arrives, only the duration remains. Terminal signals without a start, contradictory times and manual previews supply no duration samples. Existing saves begin learning from new signals. Both successful and failed endings count as the end of the wait.

For a task of age *t*, take its peers observed for longer than *t*. Other still-open tasks contribute right-censored observation times. The target is excluded. At each distinct duration, multiply survival by the fraction of the risk set that did not finish at that duration, then remove all endings and censorings at that time. Sidekin reports the first durations at which conditional survival reaches 0.5 and 0.2, minus *t*. It requires at least eight peers and an identifiable median. The 80th percentile appears only when it is identifiable. These are historical duration estimates pooled across local tasks.

## Chronological replay

The fixtures use public GitHub Actions start and update timestamps as a proxy for task signals. The first quarter of each sequence warms the local state. The remaining runs are replayed in event-time order, revealing an ending only when its timestamp arrives. For each landmark, compare the predicted median against (1) the unconditional median of observed completed durations minus elapsed time, floored at zero and (2) the median among completed peers that lasted beyond the landmark. All three error columns use exactly the same issuance decisions. MAE is in seconds. The last column counts actual remaining durations at or below the estimated 80th percentile.

| Trace | Age | Eligible | Forecasts | Conditional MAE | Unconditional MAE | Completed survivors MAE | Upper bound coverage |
|---|---:|---:|---:|---:|---:|---:|---:|
| Sidekin, 60 runs | 1 min | 41 | 41 | 35.1 | 36.0 | 35.1 | 24/41 |
| Sidekin | 3 min | 8 | 0 | — | — | — | — |
| GitHub CLI, 220 runs | 1 min | 165 | 165 | 57.8 | 57.8 | 57.8 | 115/165 |
| GitHub CLI | 3 min | 165 | 165 | 57.8 | 57.8 | 57.8 | 115/165 |
| GitHub CLI | 5 min | 165 | 165 | 57.7 | 57.8 | 57.8 | 115/165 |
| GitHub CLI | 7 min | 162 | 162 | 54.9 | 54.9 | 54.9 | 112/162 |
| GitHub CLI | 10 min | 54 | 53 | 47.8 | 61.1 | 47.9 | 39/53 |

No Sidekin holdout run reached the five-minute landmark. Conditioning on elapsed time accounts for most of the gain on long CLI runs. The upper historical percentile covered fewer than 80% of outcomes on both traces. Actual Codex task accuracy requires a separate evaluation.

The [Sidekin trace](../tests/fixtures/public-workflow-runs.json) and [GitHub CLI trace](../tests/fixtures/cli-trunk-timing.csv) are frozen inputs. The latter includes all 220 returned push runs of the [CLI Go workflow](https://github.com/cli/cli/actions/workflows/go.yml) on `trunk` created from August 1 through October 31, 2026, inclusive. Its five columns come from the [GitHub Actions API query](https://api.github.com/repos/cli/cli/actions/workflows/25016/runs?event=push&branch=trunk&created=2026-08-01..2026-10-31&per_page=100), paginated and sorted by start time and run ID. Update time marks the observed terminal timestamp. Each row identifies the returned attempt.

Run `npx vitest run tests/task-timing-replay.test.ts --silent=false --disableConsoleIntercept` after installing the locked development dependencies.
