# Sidekin 2.2 completion audit

This audit covers the shared macOS and Windows source Beta. The target is a reproducible GitHub project with native CI evidence, not a signed consumer release. Paid-image flows use simulated clients; verification reads no user key and makes no paid request.

## Requirement-to-evidence map

| Requirement | Implemented behavior | Primary evidence |
|---|---|---|
| One cross-platform project | Electron 43 and TypeScript share lifecycle, windows, renderers, agent adapters, persistence, workshop, and templates. | `src/`, `package.json`, `Scripts/package-desktop.mjs` |
| Floating desktop companion | Transparent, frameless, always-on-top window; tray/menu access; click-through empty pixels; display-bound clamping; single-instance behavior. | `src/main/index.ts`, `src/renderer/floating.*`, Electron E2E |
| Live concurrent task display | Three floating cards and an eight-card bounded history show provider, state, project label, and elapsed time. Completing one task leaves other live tasks running. | `src/shared/lifecycle.ts`, `tests/lifecycle.test.ts` |
| Codex adapter | Official `UserPromptSubmit` and `Stop` hooks, correct empty/JSON hook output behavior, independent install/removal, trust-review guidance, optional best-effort fallback, and a bridge process that continues working while the single UI instance is open. | `src/shared/codex.ts`, `src/main/codex-monitor.ts`, hook concurrency E2E, `tests/codex.test.ts` |
| Claude Code adapter | Independent `UserPromptSubmit`, `Stop`, `StopFailure`, and `SessionEnd` hooks with no prompt-visible bridge output. | same adapter files and tests |
| Metadata minimization | Persistent records contain provider, status, time, turn/session ID, and workspace basename; prompts, replies, code, and tool output are discarded. | `src/main/codex-monitor.ts`, privacy tests |
| Reliable recovery | Running tasks older than two hours become `interrupted` and can be cleared, preventing a permanent working state. | lifecycle engine and tests |
| Care and growth | Hunger, mood, energy, conditional care, cooldowns, bounded offline progression, streaks, temperament, journal, monotonic five-stage evolution. | `src/shared/lifecycle.ts`, `tests/lifecycle.test.ts` |
| Motion variety | 13 lifecycle states combine with 20 lineage motion profiles; reduced-motion users receive static state cues. | `src/renderer/floating.css`, catalog, verifier |
| No decorative slots | Hat, face, and aura state/IPC/UI are absent; migration drops legacy cosmetic data. | `src/shared/lifecycle.ts`, renderer, verifier |
| Local persistence | State, settings, task metadata, templates, and job recovery use atomic local writes with known-good JSON backups and corrupt-primary recovery; legacy app data migrates only into an absent Sidekin directory. | `src/main/file-store.ts`, `src/main/paths.ts`, `tests/file-store.test.ts` |
| Secure renderer boundary | Sandbox, context isolation, no Node integration, exact sender origins, runtime IPC validation, CSP, denied permissions/popups/navigation, short-lived reference tokens. | `src/main/index.ts`, `src/preload/index.ts`, verifier |
| User-owned API key | No shared key; individual key uses Electron `safeStorage` backed by Keychain or DPAPI. | `src/main/secret-store.ts` |
| Resumable generation | Every paid raw response is saved before cutout; saved stages resume without repurchase; restart and single-stage retry are explicit; the original reference path is discarded after a bounded normalized local copy. | `src/main/workshop.ts`, `tests/workshop.test.ts` |
| Safe cutout | Edge-connected adaptive flood fill removes only background-connected key color and preserves enclosed pink/purple detail. | `src/main/image-processor.ts`, synthetic pixel test |
| Pet Pack SDK | Schema 2 adds author/license/version/profile/hashes; CLI initializes, validates, packs, unpacks, and rejects code, traversal, duplicates, corruption, oversize, and tampering. Schema 1 migrates. | `Scripts/pet-pack.mjs`, `docs/PET_PACK_SDK.md`, `tests/pet-pack.test.ts` |
| Runtime catalog | 1,000 768×768 WebPs and 200 320×320 thumbnails match the 200-lineage catalog and per-file SHA-256 manifest. | `RuntimeAssets/`, `Scripts/verify-runtime-assets.mjs` |
| Full-art recovery | Accepted 1254×1254 PNGs, authoring sources, audit sheets, and full posters remain at a commit-pinned archive snapshot. | `docs/ART_ARCHIVE.md`, runtime manifest |
| Package integrity and budgets | Package verifier requires exact runtime counts, re-hashes all 1,200 copied assets, reports app/archive bytes and archive SHA-256, and rejects macOS metadata junk. | `Scripts/package-desktop.mjs` |
| License boundary | Sidekin remains explicitly proprietary; Pet Pack authors declare their own terms; runtime dependency notices are documented and copied into each package. | `LICENSE`, `THIRD_PARTY_NOTICES.md`, `docs/PET_PACK_SDK.md` |
| Real UI smoke test | The actual Electron app captures Home, floating pet, Workshop, and Settings and verifies state, loaded images, profile classes, dimensions, and nonblank entropy. | `Scripts/run-e2e.mjs` |
| Native CI | macOS and Windows jobs install from lockfile, verify, package, inspect budgets, and upload temporary artifacts. | `.github/workflows/desktop.yml` |

## Reproducible checks

```bash
npm ci
npm run verify
npm run make
```

`npm run verify` performs zero-warning linting, TypeScript checking, deterministic unit/integration/security tests, a clean build, asset hash/dimension/budget verification, desktop contract checks, and a real Electron E2E capture. None of these steps uses a real API key.

Historical visual QA can be inspected through the text audits on main and full contact sheets/source assets on `archive/full-png-corpus-v2.1`. See `docs/ART_ARCHIVE.md` for a separate-worktree workflow.

## Boundaries

- No real OpenAI API key or paid image request was used during this audit.
- Local screenshots use synthetic task labels and isolated temporary application data.
- macOS output is ad-hoc signed only; it is not Developer ID signed or notarized.
- Windows output is not Authenticode signed.
- CI artifacts are verification evidence, not consumer-ready installers.
- A Windows CI claim becomes current only after the exact pushed commit has a green native Windows job.
- The retained Swift code is historical provenance and macOS art tooling, not the product runtime.

Accurate statement: **Sidekin 2.2 is a locally verified cross-platform source Beta with native macOS and Windows CI/package gates, recoverable source art, and no claim of signed public distribution or author-funded API validation.**
