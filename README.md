<div align="center">
  <img src="docs/readme/hero.jpg" alt="Sidekin — a local-first macOS companion for Codex" width="100%">
  <br><br>
  <img src="docs/readme/app-icon.png" alt="Sidekin app icon" width="96">
  <br>
  <img src="https://img.shields.io/badge/local%20suite-passing-21c55d?style=flat-square" alt="Local verification suite passing">
  <img src="https://img.shields.io/badge/macOS-14%2B-0b1026?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or newer">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-0b1026?style=flat-square&logo=apple&logoColor=white" alt="Apple Silicon arm64">
  <img src="https://img.shields.io/badge/Swift-6.0-f05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/lineages-100-26c6c3?style=flat-square" alt="100 lineages">
  <img src="https://img.shields.io/badge/forms-500-8b5cf6?style=flat-square" alt="500 forms">
  <br><br>
  <strong>A native floating companion that turns Codex task activity into care, growth, and evolution.</strong>
  <br>
  Local-first. No account. No bundled API key. No prompt or code collection.
  <br><br>
  <a href="#why-sidekin">Why Sidekin</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#100-lineages--500-forms">Gallery</a> ·
  <a href="#privacy-boundary">Privacy</a> ·
  <a href="#verification">Verification</a>
</div>

## Why Sidekin

Most desktop pets are decorative overlays. Sidekin has a persistent life of its own: it gets hungry and tired, reacts to your Codex workflow, earns growth from completed work, and evolves through a visually continuous lineage.

| Reactive companion | Real care loop | Deep lineage system | Resumable workshop |
|---|---|---|---|
| Running, completed, and failed Codex states drive visible feedback. | Hunger, mood, energy, feeding, play, sleep, wake, and local saves. | 100 built-in lineages, five audited stages each, across ten radically different categories. | Generate 1–8 stages, save every paid result immediately, retry one stage, or continue after failure. |

Sidekin is intentionally broader than an animal pet collection. Its catalog includes mythic beings, unmistakably nonhuman humanoids, deities, mecha, vehicles, plants, fungi, minerals, artifacts, food beings, weather systems, abstract entities, architecture, and distributed colonies.

## At a glance

| | Current local Beta |
|---|---|
| Version | `1.4.0` · Build 7 |
| Platform | macOS 14+ · Apple Silicon `arm64` |
| Stack | Swift 6 · SwiftUI · AppKit · Security / Keychain |
| Built-in content | 100 lineages · 500 transparent `1254×1254` PNG forms |
| Growth | Core Egg → First Spark → Shifting Form → Ascension → Crown Form |
| Codex response | Running · completed · failed |
| Storage | Local JSON, template packages, stage images, and resumable jobs |
| Distribution scope | Source project and local Beta; no public signed app release |

## Quick start

Sidekin is currently built from source. Git LFS is required because the audited visual corpus is intentionally large.

```bash
git lfs install
git clone https://github.com/limingrui679-design/Sidekin.git
cd Sidekin
./Scripts/run-all-checks.sh
./Scripts/build-app.sh
```

The verified local app is created at `artifacts/Sidekin.app`. To launch it intentionally:

```bash
./Scripts/run-app.sh
```

> Sidekin is not notarized for independent consumer distribution. This repository publishes source and reproducible local verification tooling, not a public downloadable macOS release.

## Five stages, one identity

Every lineage defines a persistent existence type, silhouette logic, material system, energy motif, locomotion class, five named forms, and stage-specific visual anchors.

![Three Sidekin lineages evolving through all five audited stages](docs/readme/evolution.jpg)

The final audit checks common-sense anatomy or construction, identity continuity, species or existence-type drift, insufficient change between stages, nonhuman-humanoid compliance, cutout quality, and readability at the 205–235 px desktop size.

## 100 lineages · 500 forms

![Ten Sidekin categories represented by final legendary forms](docs/readme/catalog.jpg)

The catalog contains ten lineages in each category:

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

Humanoid silhouettes remain unmistakably nonhuman: the art standard forbids real people, children, realistic human skin, realistic human hair, and ordinary human faces.

All 500 final images existed before the 100-lineage audit began. The repair pass produced 77 raw candidates for 74 stage targets across 61 lineages before acceptance. The evidence is reviewable in:

- [`docs/LINEAGE_AUDIT.md`](docs/LINEAGE_AUDIT.md) — one result for every lineage
- [`ArtSources/AuditSheets`](ArtSources/AuditSheets) — 20 five-lineage audit sheets
- [`ArtSources/PET_THEME_CATALOG.json`](ArtSources/PET_THEME_CATALOG.json) — machine-readable source of truth
- [`ArtSources/ART_PRODUCTION_500.md`](ArtSources/ART_PRODUCTION_500.md) — production and continuity constraints

## Care, growth, and Codex response

- Transparent floating macOS panel plus menu bar access
- Hunger, mood, and energy with feed, play, sleep, and wake actions
- Automatic local persistence and offline care progression
- Optional Codex Hooks for immediate lifecycle events
- Session-log fallback that classifies lifecycle state only
- Completed tasks grant growth once per unique Codex turn
- Running, success, and failure states drive animation and emotional feedback
- Hats, glasses / face accessories, and aura / particle cosmetic slots

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

### Bring your own API key

Sidekin never includes the developer's API key. Image generation is optional and uses the individual user's own OpenAI API key and OpenAI API account. The key is stored in that user's macOS Keychain.

Without a key, the floating companion, all 100 built-in lineages, care and growth, local saves, Codex reactions, and existing custom templates remain fully usable.

Because model capabilities and prices can change, consult the current [GPT Image model documentation](https://developers.openai.com/api/docs/models), [image generation guide](https://developers.openai.com/api/docs/guides/image-generation), and [API pricing page](https://developers.openai.com/api/docs/pricing). The app shows its estimate before a request is sent.

## Privacy boundary

| Data or action | Leaves the Mac? |
|---|---|
| Care state, growth, wardrobe, and selected lineage | No |
| Codex prompts, responses, code, tool output, and project files | No — Sidekin does not read or save them |
| Codex lifecycle classification: running, completed, failed | No |
| Custom templates, raw stages, processed stages, and resumable jobs | No |
| User's API key | No — stored in macOS Keychain |
| Confirmed image-generation description and required visual references | Yes — only when the user explicitly confirms an OpenAI Image API request |

Local files are stored under:

```text
~/Library/Application Support/Sidekin/pet-state.json
~/Library/Application Support/Sidekin/PetTemplates/
~/Library/Application Support/Sidekin/GenerationJobs/
```

On first use after the rename, Sidekin performs a best-effort migration of the legacy local application-support directory. Existing data in a new Sidekin directory is never overwritten.

## Architecture

```text
SidekinApp
├── SidekinCore          care, growth, persistence, themes, Codex classification
├── SidekinCreator       Keychain, image API, cutout pipeline, resumable jobs
├── SidekinBridge        minimal lifecycle-event writer
├── SidekinSelfTest      deterministic local behavior checks
└── SidekinAPISelfTest   mocked generation and editing checks
```

One Swift package keeps the floating companion, event bridge, growth engine, template system, verification executables, and release scripts on a shared source of truth.

## Verification

```bash
./Scripts/run-all-checks.sh
./Scripts/package-release.sh
```

The project includes **31 local checks** and **6 mocked API checks**, plus catalog, audit, English-text, image-integrity, debug-build, Release-build, archive, architecture, signing, and manifest verification. Mock checks never read a real API key or incur API charges.

The release manifest records the version, build number, minimum macOS version, architecture, source commit, signing state, application-file hashes, and hashes for all 500 character assets. Packaging rejects corrupt ZIPs, macOS metadata, missing resources, architecture drift, and manifest mismatch.

The same commands are CI-ready, but this initial GitHub publication does not claim a hosted Actions run. The verified arm64 archive remains local build evidence, not a consumer-ready public release.

## Repository guide

| Path | Purpose |
|---|---|
| [`Sources`](Sources) | Native app, core engine, creator pipeline, bridge, and executable checks |
| [`ArtSources`](ArtSources) | Catalog, prompts, curated sources, repair candidates, and audit sheets |
| [`Scripts`](Scripts) | Art, verification, build, package, manifest, and optional release tooling |
| [`docs/LINEAGE_AUDIT.md`](docs/LINEAGE_AUDIT.md) | Final 100-lineage visual QA results |
| [`docs/COMPLETION_AUDIT.md`](docs/COMPLETION_AUDIT.md) | Feature and evidence-bound completion audit |
| [`docs/RELEASING.md`](docs/RELEASING.md) | Optional future signed-distribution path |

## Project status

Sidekin is a real, tested local macOS Beta and an openly reviewable GitHub source project. It is not represented as a notarized public product, a production deployment, or a real-API end-to-end validation performed with the author's key.

The repository currently has no reuse license. Source and art are visible for review, but no permission to copy, redistribute, or create derivatives is granted until a license is added.

## Acknowledgements

The README structure takes cues from strong macOS and desktop-companion repositories—visual identity first, a concise value proposition, quick start near the top, explicit privacy and platform limits, and deeper verification details below—while all Sidekin copy, code, and visual assets remain project-specific.
