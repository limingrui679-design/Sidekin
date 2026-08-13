# CainiaoPet 100-Theme / 500-Form Art Production Standard

CainiaoPet contains 100 independent five-stage lineages, not 100 isolated form names. The source of truth is the ten category files in `ArtSources/ThemeCatalog/`. The generated `ArtSources/PET_THEME_CATALOG.json` combines them into a machine-readable production manifest.

Each lineage defines a unique existence anchor, silhouette topology, locomotion class, material system, energy motif, five form names, five concise introductions, and five stage-specific visual anchors. Ten themes belong to each of these categories:

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

## Shared production prompt

Use case: `stylized-concept`

Create exactly one complete full-body subject for a premium competitive-game macOS floating pet. Use a polished high-end 3D game-character render, a deliberately readable silhouette, a clear focal feature, production-quality construction, crisp material separation, controlled highlights, and a disciplined palette. The result must feel like an original collectible arena companion rather than a sticker, generic mascot, toy icon, or imitation of an existing franchise.

Follow the selected theme's existence, silhouette, movement, material, energy, and current-stage visual anchors exactly. Non-animal themes must remain genuinely non-animal: do not add a generic face, four animal legs, dragon anatomy, fox ears, horns, or humanoid armor unless the catalog explicitly requires them.

Stage progression must be structural:

- Stage I is a compact origin container, seed, core, field, diagram, module, or incomplete organism. It must not expose the complete mature limb set.
- Stage II reveals the defining existence type and basic locomotion.
- Stage III establishes the signature topology, tool, organ, or system.
- Stage IV changes stance and functional anatomy for a clear ascension.
- Stage V reaches a crown form through a major outline, scale, formation, or system change.

Composition: centered square canvas, one complete subject, all components visible, generous padding, readable at 205–235 px, and a three-quarter view unless the stage anchor explicitly calls for a radial, profile, top-down, diagrammatic, or architectural composition.

Background for removal: perfectly flat `#00ff00` with no floor, shadow, gradient, fog, texture, reflection, vignette, or lighting variation. If green is essential to the subject, use a flat alternate key color that is absent from the subject. Never place the key color on the subject.

Hard constraints: no scenery, detached decorative props unrelated to the existence anchor, frame, border, text, letters, numbers, logo, watermark, contact shadow, duplicate subject, cropped component, generic upright humanoid substitution, or recolor-only evolution.

## Required files

- Exactly 500 final resources: 100 theme IDs × 5 canonical stages.
- Resource name: `<theme-id>-<stage-id>.png`.
- Canonical stage IDs: `egg`, `hatchling`, `juvenile`, `ascended`, `legendary`.
- Final canvas: `1254×1254` transparent PNG.
- Curated source: `ArtSources/FiveStage/<Theme>/<stage>-source.png`.
- App resource: `Sources/CainiaoPetApp/Resources/Characters/<theme-id>-<stage-id>.png`.

## Acceptance gates

- Every file is decodable, binary-unique, `1254×1254`, and has four transparent corners.
- Visible occupancy remains between 4.5% and 72% of the square canvas.
- Tiny detached alpha islands and chroma-key edge spill are rejected.
- Same-lineage pairs at or above `0.82` silhouette IoU enter an appearance review; they are rejected only when normalized RGBA appearance similarity is also at or above `0.90`.
- Same-stage cross-theme pairs at or above `0.86` silhouette IoU enter an appearance review; they are rejected only when normalized RGBA appearance similarity is also at or above `0.92`.
- The two-stage comparison prevents intentionally compact eggs or round cores from failing merely because their outer masks are similar while still rejecting near-duplicate visible designs.
- Every high-IoU candidate remains subject to visual inspection even when its appearance score is below the automated rejection threshold.
- Every stage is checked at desktop scale for clean cutout, full construction, anchor retention, readable focal feature, and stage continuity.
- Every lineage is checked against all 99 other themes for silhouette topology, locomotion, materials, energy motif, and existence-type collision.
- Weak or derivative images are regenerated; quantity never lowers the standard.

Run `Scripts/verify-theme-catalog.sh` to confirm the 100-theme source and generated catalog match. Run `Scripts/verify-character-assets.swift` after all 500 resources exist. The individual final review record is in `docs/LINEAGE_AUDIT.md`; its 20 visual contact sheets are in `ArtSources/AuditSheets/`.
