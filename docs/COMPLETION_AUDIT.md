# Sidekin 2.1 Cross-Platform Completion Audit

This audit covers the shared macOS and Windows source Beta. The completion target is a reproducible GitHub project with native CI evidence on both operating systems, not a signed consumer release. A simulated image client is used for paid-flow tests; no author API key or paid request is part of verification.

## Requirement-by-Requirement Evidence

| Requirement | Current implementation | Primary evidence |
|---|---|---|
| One macOS + Windows project | One Electron 43 and TypeScript runtime implements lifecycle, windows, renderers, Codex monitoring, persistence, workshop, and templates. Platform branches are limited to OS paths, window details, secure storage, and packaging. | `src/`, `package.json`, `Scripts/package-desktop.mjs`, `.github/workflows/desktop.yml` |
| Floating desktop companion | A transparent, frameless, always-on-top window remains separate from the Command Center and is available from the macOS menu bar or Windows system tray. | `src/main/index.ts`, isolated runtime capture in `artifacts/previews/` |
| Official-style live task display | Up to three floating task cards show running, completed, and failed states, project label, and live elapsed time. A five-item bounded history is persisted locally. | `src/renderer/floating.ts`, `src/shared/lifecycle.ts`, runtime capture report |
| Real Codex response without content collection | The monitor reads lifecycle event type, turn ID, timestamp, and working-directory basename only. It does not retain prompt, response, code, reasoning, or tool-output fields. Optional Hooks provide lower-latency signals and preserve unrelated handlers. | `src/shared/codex.ts`, `src/main/codex-monitor.ts`, `tests/codex.test.ts` |
| Concurrent tasks | Completing one task does not stop the working animation while another task remains live. Each turn is deduplicated before rewards are applied. | `tests/lifecycle.test.ts` |
| Rich motion system | Thirteen named states are implemented: four idle motions, two working motions, celebration, failure, feed, play, sleep, wake, and evolution. | `src/shared/types.ts`, `src/renderer/floating.css`, `Scripts/verify-desktop.mjs` |
| No cosmetic-slot subsystem | The former hat, face, and aura slots are removed from state, IPC, preload, settings, and floating rendering. Migration drops their legacy data instead of carrying it forward. | `src/shared/lifecycle.ts`, `src/renderer/index.html`, `Scripts/verify-desktop.mjs` |
| Care, growth, and evolution | Hunger, mood, energy, feed, play, sleep/wake, offline progression, five stages, monotonic evolution, and stage previews share one deterministic engine. | `src/shared/lifecycle.ts`, `tests/lifecycle.test.ts` |
| Local persistence | Pet state, settings, task-card metadata, templates, and generation recovery are written atomically to the OS application-data directory. Legacy saves are migrated without overwriting an existing Sidekin directory. | `src/main/file-store.ts`, `src/main/paths.ts`, `src/main/state-service.ts` |
| User-owned API key | Sidekin contains no shared key. The individual user may store their own key through Electron `safeStorage`, backed by macOS Keychain or Windows DPAPI. | `src/main/secret-store.ts`, `src/main/index.ts` |
| Resumable paid generation | Every raw response is atomically saved before cutout processing. Existing raw stages can finish locally without a key, interruptions resume without requesting saved stages again, and restart-from-stage is explicit. | `src/main/workshop.ts`, `tests/workshop.test.ts` |
| Pink/purple-safe cutout | Background removal flood-fills only edge-connected adaptive key color, preserving enclosed pink and purple subject regions. | `src/main/image-processor.ts`, synthetic image test in `tests/workshop.test.ts` |
| Template management | Rename, delete, import, export, local stage replacement, single-stage regeneration, saved-raw retry, and corrupt-image rejection are implemented in the shared runtime. | `src/main/template-store.ts`, `src/main/workshop.ts`, renderer management UI, tests |
| Cost boundary | Low, medium, and high tiers show output estimates before generation or single-stage regeneration. Confirmation states that reference input cost is additional and the user's account is charged. | `src/renderer/app.ts` |
| Visual corpus | The verifier requires exactly 200 catalog lineages and all 1,000 named stage assets. The original 100-category audit and the separate 100-lineage tag-based expansion audit together provide one visual QA result per lineage. | `ArtSources/PET_THEME_CATALOG.json`, `docs/LINEAGE_AUDIT.md`, `docs/EXPANSION_AUDIT.md`, `Scripts/verify-desktop.mjs` |
| Renderer security | Renderers use sandboxing, context isolation, no Node integration, a narrow preload API, sender validation, CSP, denied permissions, denied popups, and blocked remote navigation. | `src/main/index.ts`, `src/preload/index.ts`, `Scripts/verify-desktop.mjs` |
| README presentation | The centered poster uses a dense action ensemble with changed poses, foreground cropping, overlap, atmospheric depth, and no catalog-style empty ring; the README also includes a 20-lineage sampler and all-200 contact sheet. | `ArtSources/READMEHero/hero-dynamic-source.png`, `docs/readme/hero.jpg`, `docs/readme/all-200.jpg`, `docs/readme/live-desktop.jpg` |
| Native packaging evidence | Electron Packager 20 packages the current operating system; GitHub Actions runs the same verification and creates artifacts on native macOS and Windows runners. | `Scripts/package-desktop.mjs`, `.github/workflows/desktop.yml` |

## Reproducible Checks

```bash
npm ci
npm run verify
npm run capture
npm run media:runtime
npm run make
```

`npm run verify` performs TypeScript checking, deterministic tests, a clean build, renderer/security inspection, exact motion enumeration, and the 200-lineage / 1,000-form gate. `npm run capture` uses an isolated temporary application-data directory with synthetic lifecycle and workshop data; it does not inspect the user's API key or send a network request.

The historical macOS art pipeline remains separately reproducible:

```bash
./Scripts/verify-theme-catalog.sh
swift Scripts/verify-lineage-audit.swift
node Scripts/verify-expansion-plan.mjs --full
```

## Boundaries

- No real OpenAI API key was used and no paid API request was made during this audit.
- Runtime captures use synthetic task labels and temporary local data.
- The source Beta and CI artifacts are not Developer ID signed, notarized, Microsoft code-signed, or presented as consumer-ready installers.
- The earlier Swift application remains for provenance and macOS art tooling only; the product runtime described here is the shared TypeScript implementation.
- A GitHub Actions badge is evidence only when the exact pushed commit has green macOS and Windows jobs.

The accurate product statement is: **a locally verified, cross-platform source Beta with one shared runtime, native macOS and Windows packaging gates, and no claim of signed public distribution or author-funded API validation.**
