<div align="center">
  <a href="docs/readme/poster-arena-convergence.png"><img src="docs/readme/poster-arena-convergence.jpg" alt="Arena Convergence — Sidekin creatures charging through a cosmic arena" width="100%"></a>
  <br><br>
</div>

<h1 align="center">Sidekin</h1>

<div align="center">
  <img src="docs/readme/app-icon-readme.png" alt="Sidekin app icon" width="96">
  <br>
  <img src="https://img.shields.io/badge/macOS-13%2B-0b1026?style=flat-square&logo=apple&logoColor=white" alt="macOS 13 or newer">
  <img src="https://img.shields.io/badge/Windows-10%2F11-0b1026?style=flat-square&logo=windows11&logoColor=white" alt="Windows 10 and 11">
  <img src="https://img.shields.io/badge/Electron-43-47848f?style=flat-square&logo=electron&logoColor=white" alt="Electron 43">
  <a href="https://github.com/limingrui679-design/Sidekin/actions/workflows/desktop.yml"><img src="https://github.com/limingrui679-design/Sidekin/actions/workflows/desktop.yml/badge.svg" alt="macOS and Windows desktop verification"></a>
  <a href="https://github.com/limingrui679-design/Sidekin/actions/workflows/codeql.yml"><img src="https://github.com/limingrui679-design/Sidekin/actions/workflows/codeql.yml/badge.svg" alt="CodeQL analysis"></a>
  <img src="https://img.shields.io/badge/lineages-200-26c6c3?style=flat-square" alt="200 lineages">
  <img src="https://img.shields.io/badge/forms-1%2C000-8b5cf6?style=flat-square" alt="1,000 forms">
  <br><br>
  <strong>A live floating companion that turns Codex task activity into care, growth, and evolution.</strong>
  <br>
  Local-first. No Sidekin account. No bundled API key. No prompt or code collection.
  <br><br>
  <a href="#why-sidekin">Why Sidekin</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#how-sidekin-works">Workflow</a> ·
  <a href="#visual-gallery">Gallery</a> ·
  <a href="#privacy-boundary">Privacy</a> ·
  <a href="#verification">Verification</a>
</div>

## Why Sidekin

Most desktop pets are decorative overlays. Sidekin has a persistent life of its own: it gets hungry and tired, reacts to your Codex workflow, earns growth from completed work, and evolves through a visually continuous lineage.

| Live companion | Real care loop | Deep lineage system | Resumable workshop |
|---|---|---|---|
| Running, completed, and failed Codex tasks become timed local cards and animated pet reactions. | Hunger, mood, energy, feeding, play, sleep, wake, and local saves. | 200 built-in lineages and 1,000 audited forms: a ten-category foundation plus a tag-based expansion. | Generate 1–8 stages, save every paid result immediately, retry one stage, or continue after failure. |

Sidekin is intentionally broader than an animal pet collection. Its catalog includes mythic beings, unmistakably nonhuman humanoids, deities, mecha, vehicles, plants, fungi, minerals, artifacts, food beings, weather systems, abstract entities, architecture, and distributed colonies.

![Sidekin Command Center and transparent floating companion showing live Codex task cards](docs/readme/live-desktop-readme.jpg)

## How Sidekin works

<p align="center">
  <img src="docs/readme/sidekin-workflow.svg" alt="Sidekin compact workflow from local Codex lifecycle signals through classification and care state to the floating companion" width="100%">
</p>

The core path remains local: Sidekin classifies lifecycle metadata, updates one deterministic care-and-growth state, renders the companion, and saves only bounded local state. The separate image workshop contacts the OpenAI Image API only after the user confirms a request with their own key.

## Visual gallery

Arena Convergence leads the page. The eight remaining compositions each use one full-width lightweight preview below, while a click opens the preserved full-resolution source.

### Cosmic Grand Assembly

[![Cosmic Grand Assembly Sidekin poster with a dense full-catalog constellation](docs/readme/hero-readme.jpg)](docs/readme/hero.jpg)

*A starfield ensemble spanning mythic beings, mecha, architecture, artifacts, and abstract life.*

### Evolution Odyssey

[![Evolution Odyssey Sidekin poster with small forms traveling toward crown forms](docs/readme/poster-evolution-odyssey.jpg)](docs/readme/poster-evolution-odyssey.png)

*Growth and transformation moving through one connected world.*

### Prismatic Pet Festival

[![Prismatic Pet Festival Sidekin poster with playful nonhuman companions](docs/readme/poster-prismatic-festival.jpg)](docs/readme/poster-prismatic-festival.png)

*Bright companionship, racing, dancing, and playful scale changes.*

### Chronicle of Ten Worlds

[![Chronicle of Ten Worlds Sidekin poster spanning ten creature categories](docs/readme/poster-chronicle-ten-worlds.jpg)](docs/readme/poster-chronicle-ten-worlds.png)

*Ten catalog categories joined into one epic world map.*

### Neon Night League

[![Neon Night League Sidekin poster with nonhuman pets racing through a futuristic arena](docs/readme/poster-neon-night-league.jpg)](docs/readme/poster-neon-night-league.png)

*High-speed competitive action across a neon creature arena.*

### Codex Companion Workshop

[![Codex Companion Workshop Sidekin poster showing care, rest, play, and task activity](docs/readme/poster-companion-workshop.jpg)](docs/readme/poster-companion-workshop.png)

*Feeding, rest, play, study, and live task response inside one shared workshop.*

### Mythic Dawn Assembly

[![Mythic Dawn Assembly Sidekin poster with nonhuman deities, spirits, plants, and constructs](docs/readme/poster-mythic-dawn.jpg)](docs/readme/poster-mythic-dawn.png)

*Monumental nonhuman mythology formed from plants, crystal, weather, and divine constructs.*

### Microverse Mayhem

[![Microverse Mayhem Sidekin poster with tiny collectives and enormous evolved guardians](docs/readme/poster-microverse-mayhem.jpg)](docs/readme/poster-microverse-mayhem.png)

*Tiny societies, living habitats, and enormous evolved guardians.*

[Open the dedicated visual gallery](docs/GALLERY.md) for the selected homepage poster and all eight supporting themes.

## At a glance

| | Current local Beta |
|---|---|
| Version | `2.1.0-beta.1` cross-platform source Beta |
| Platform | macOS 13+ · Windows 10/11 · 64-bit |
| Stack | Electron 43 · TypeScript · secure isolated renderers |
| Built-in content | 200 lineages · 1,000 transparent `1254×1254` PNG forms |
| Growth | Core Egg → First Spark → Shifting Form → Ascension → Crown Form |
| Codex response | Live task cards · running · completed · failed · elapsed time |
| Storage | Local JSON, template packages, stage images, and resumable jobs |
| Credential storage | macOS Keychain · Windows DPAPI through Electron `safeStorage` |
| Distribution scope | Public source-Beta archives for inspection; no signed consumer installer |

## Quick start

Sidekin is currently built from source. Git LFS is required because the audited visual corpus is intentionally large.

The [`v2.1.0-beta.1` prerelease](https://github.com/limingrui679-design/Sidekin/releases/tag/v2.1.0-beta.1) retains native macOS and Windows CI archives, portable checksum files, package reports, and a tracked-source snapshot. The macOS archive is ad-hoc signed and the Windows archive is unsigned; neither is a consumer-trust or store-distribution claim.

```bash
git lfs install
git clone https://github.com/limingrui679-design/Sidekin.git
cd Sidekin
npm ci
npm run verify
npm start
```

To create an unpacked app for the current operating system:

```bash
npm run package
```

> Sidekin does not publish signed consumer installers. The prerelease archives are transparent source-Beta build evidence and must be verified with their adjacent SHA-256 files.

## Five stages, one identity

Every lineage defines a persistent existence type, silhouette logic, material system, energy motif, locomotion class, five named forms, and stage-specific visual anchors.

![Three Sidekin lineages evolving through all five audited stages](docs/readme/evolution-readme.jpg)

The showcase deliberately exposes the full progression instead of selecting isolated hero poses. Nova keeps one bow-based combat language from its first compact starbow to its crown-scale compass bow. Walking Treehouse advances by architecture—not recolor—from one room to a two-room bridge home, a terraced village, and a circular crown borough.

The final audit checks common-sense anatomy or construction, identity continuity, species or existence-type drift, insufficient change between stages, nonhuman-humanoid compliance, cutout quality, and readability at the 205–235 px desktop size.

## 200 lineages · 1,000 forms

### Twenty-lineage sampler

![Twenty Sidekin lineages represented by final legendary forms](docs/readme/showcase-20-readme.jpg)

This sampler pairs two contrasting lineages from every original category so the gallery shows variation within a category—not only one mascot per label.

The first 100 lineages form a balanced foundation with ten lineages in each category:

1. Fauna & Mythic
2. Machines & Vehicles
3. Flora & Fungi
4. Mineral & Geological
5. Artifacts & Instruments
6. Food & Alchemy
7. Elemental & Weather
8. Cosmic & Abstract
9. Living Architecture
10. Collective Systems

The second 100 lineages use searchable free-form tags rather than forcing every idea back into those ten buckets. This expansion adds nonhuman champions, spirits, legendary creatures, deities, racing forms, guardians, and mecha while preserving the same five-stage data contract and visual continuity rules.

### Every built-in lineage

[![All 200 Sidekin lineages represented by their final legendary forms](docs/readme/all-200-readme.jpg)](docs/readme/all-200.jpg)

The complete contact sheet is generated directly from the same 200-theme catalog and final assets consumed by the app. It is an inventory view, not a separate hand-picked marketing set. Click it to inspect the full-resolution sheet.

Humanoid silhouettes remain unmistakably nonhuman: the art standard forbids real people, children, realistic human skin, realistic human hair, and ordinary human faces.

The original 500 images existed before the first 100-lineage audit began. That audit plus a later README showcase review produced 83 raw candidates for 80 stage targets across 63 lineages before acceptance. A second, separately tracked expansion added another 100 lineages and 500 forms; all 100 expansion sequences were reviewed, six lineages were regenerated and reprocessed after visible findings, and one additional hatchling received a hash-pinned final normalization after the automated readability gate. The evidence is reviewable in:

- [`docs/LINEAGE_AUDIT.md`](docs/LINEAGE_AUDIT.md) — one result for each of the original 100 lineages
- [`docs/EXPANSION_AUDIT.md`](docs/EXPANSION_AUDIT.md) — one result for each of the 100 expansion lineages
- [`ArtSources/AuditSheets`](ArtSources/AuditSheets) — 20 five-lineage audit sheets
- [`ArtSources/Expansion200/ReviewSheets`](ArtSources/Expansion200/ReviewSheets) — 20 final expansion asset sheets
- [`ArtSources/PET_THEME_CATALOG.json`](ArtSources/PET_THEME_CATALOG.json) — machine-readable source of truth
- [`ArtSources/ART_PRODUCTION_500.md`](ArtSources/ART_PRODUCTION_500.md) — production and continuity constraints

## Care, growth, and Codex response

- Transparent always-on-top floating window plus macOS menu-bar or Windows system-tray access
- Live local task cards with task label, workspace, state, and elapsed time
- Thirteen motion states: four idle variations, two working motions, celebration, failure, feed, play, sleep, wake, and evolution
- Hunger, mood, and energy with feed, play, sleep, and wake actions
- Automatic local persistence and offline care progression
- Optional Codex Hooks for immediate lifecycle events
- Session-log fallback that classifies lifecycle state only
- Completed tasks grant growth once per unique Codex turn
- Running, success, and failure states drive animation and emotional feedback

Hook installation and removal preserve unrelated user configuration. Sidekin owns only handlers containing its own bridge marker, and removes the legacy bridge marker during migration.

## Pet Workshop

Pet Workshop supports:

- Text Original, Reference Restyle, and High-Fidelity Reference modes
- One to eight named stages
- Draft `low`, Standard `medium`, and Final `high` quality tiers
- Dynamic output-cost estimates before confirmation
- Immediate persistence of every raw response before background removal
- Continue after interruption, restart from a selected stage, or regenerate one stage
- Free local reprocessing of an already paid raw image without an API key
- Edge-connected adaptive background removal that protects interior pink and purple colors
- Raw / processed side-by-side previews
- Rename, delete, import, export, replace, and regenerate template stages

![Pet Workshop showing paid raw persistence, local cutout recovery, stage controls, and user-owned API key storage](docs/readme/workshop-readme.jpg)

### Bring your own API key

Sidekin never includes the developer's API key. Image generation is optional and uses the individual user's own OpenAI API key and OpenAI API account. The key is protected by macOS Keychain or Windows DPAPI through the operating system's secure storage.

Without a key, the floating companion, all 200 built-in lineages, care and growth, local saves, Codex reactions, and existing custom templates remain fully usable.

Because model capabilities and prices can change, consult the current [GPT Image model documentation](https://developers.openai.com/api/docs/models), [image generation guide](https://developers.openai.com/api/docs/guides/image-generation), and [API pricing page](https://developers.openai.com/api/docs/pricing). The app shows its estimate before a request is sent.

## Privacy boundary

| Data or action | Leaves this computer? |
|---|---|
| Care state, growth, selected lineage or template, and local task cards | No |
| Codex prompts, responses, code, tool output, and project files | No — Sidekin does not collect, extract, or persist them |
| Codex lifecycle classification: running, completed, failed | No |
| Custom templates, raw stages, processed stages, and resumable jobs | No |
| User's API key | Only to `api.openai.com` when the user confirms an image request; encrypted locally through macOS Keychain or Windows DPAPI |
| Confirmed image-generation description and required visual references | Yes — only when the user explicitly confirms an OpenAI Image API request |

Local files are stored in the operating-system application-data directory:

```text
macOS:   ~/Library/Application Support/Sidekin/
Windows: %APPDATA%\Sidekin\
```

On first use after the rename, Sidekin performs a best-effort migration of the legacy local application-support directory. Existing data in a new Sidekin directory is never overwritten.

## Architecture

```text
Electron main process
├── shared lifecycle     care, growth, motion, themes, Codex classification
├── secure preload       narrow validated renderer API
├── control renderer     care, gallery, live tasks, workshop, settings
├── floating renderer    transparent pet, actions, animations, task cards
├── creator services     image API, cutout pipeline, resumable jobs
└── platform adapters    windows, tray, paths, Keychain / DPAPI, packaging
```

The macOS and Windows apps use one TypeScript implementation. Platform branches are confined to window behavior, paths, credential encryption, and packaging. The earlier Swift implementation is retained only as historical provenance and macOS art-audit tooling; it is not the shipped runtime entry point.

## Verification

```bash
npm run verify
npm run package
```

The shared runtime has deterministic lifecycle, concurrent-task, Codex metadata, workshop recovery, template safety, and pink/purple-safe cutout tests. The verifier also enforces isolated renderers, denied remote navigation and permissions, all 13 named motions, 200 lineages, 1,000 forms, the completed 100-lineage expansion ledger, and both packaging targets. Legacy art-authoring checks remain available under `Scripts/`; none of these checks reads a real API key or incurs an API charge.

The GitHub Actions matrix runs natively on `macos-latest` and `windows-latest`, creates platform ZIP artifacts, and reruns the same verification before packaging. These CI artifacts are source-Beta evidence, not signed public installers.

## Repository guide

| Path | Purpose |
|---|---|
| [`src`](src) | Shared Electron runtime, lifecycle, secure preload, renderers, Codex monitor, and workshop |
| [`tests`](tests) | Cross-platform lifecycle, live-status, security-boundary, cutout, and recovery tests |
| [`Sources/SidekinApp/Resources/Characters`](Sources/SidekinApp/Resources/Characters) | The 1,000 built-in transparent character forms consumed by both platforms |
| [`Sources`](Sources) | Historical Swift implementation and macOS-only art/provenance checks; not the shipped runtime |
| [`ArtSources`](ArtSources) | Catalog, prompts, curated sources, repair candidates, and audit sheets |
| [`Scripts`](Scripts) | Shared build/verification/media tools plus historical macOS art tooling |
| [`.github/workflows/desktop.yml`](.github/workflows/desktop.yml) | Native macOS and Windows verification and packaging matrix |
| [`.github/workflows/release.yml`](.github/workflows/release.yml) | Tagged prerelease build, checksum, and GitHub Release publication |
| [`docs/LINEAGE_AUDIT.md`](docs/LINEAGE_AUDIT.md) | Final visual QA results for the original 100 lineages |
| [`docs/EXPANSION_AUDIT.md`](docs/EXPANSION_AUDIT.md) | Final visual QA results for the 100-lineage expansion |
| [`docs/COMPLETION_AUDIT.md`](docs/COMPLETION_AUDIT.md) | Feature and evidence-bound completion audit |
| [`docs/RELEASING.md`](docs/RELEASING.md) | Current source-build and native CI packaging guide |

## Project status

Sidekin 2.1.0-beta.1 is an openly reviewable macOS and Windows source Beta. The same runtime is tested on both platforms, locally packaged and launched on macOS, and packaged by the repository's native Windows CI job. It is not represented as a signed public product, a production deployment, external adoption, or a real-API end-to-end validation performed with the author's key.

The repository is proprietary and all rights are reserved. Source and art are visible for review, but no permission to copy, redistribute, or create derivatives is granted by the repository's [`LICENSE`](LICENSE).

## Acknowledgements

The README structure takes cues from strong macOS and desktop-companion repositories—visual identity first, a concise value proposition, quick start near the top, explicit privacy and platform limits, and deeper verification details below—while all Sidekin copy, code, and visual assets remain project-specific.
