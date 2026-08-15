# Sidekin Expansion 200

This directory records the second 100 built-in Sidekin lineages. Together with the original catalog cohort, it raises the application corpus to 200 lineages and 1,000 five-stage forms.

## Tracked evidence

- `lineages.json`: the 100 tag-based lineage definitions merged into the master catalog;
- `Prompts/`: one five-stage lineup prompt per expansion lineage;
- `POSTER_CANON_MAP.json`: mappings from existing poster subjects to catalog IDs;
- `progress.json`: 100 generated, 100 processed, and 100 reviewed checkpoints;
- `ReviewSheets/assets-01.jpg` through `assets-20.jpg`: final five-lineage visual review sheets;
- `FINAL_ASSET_OVERRIDES.json`: hash-pinned deterministic final normalization for the one asset that missed the alpha-occupancy readability gate.

The 500 final expansion PNGs are tracked once, in `Sources/SidekinApp/Resources/Characters`, beside the original 500 assets consumed by both desktop platforms. Local lineup, split-panel, and duplicate resource folders are intentionally ignored so the repository and release archive do not store the same final images twice.

## Verification

```bash
node Scripts/apply-expansion-asset-overrides.mjs
node Scripts/make-expansion-review-sheets.mjs
node Scripts/verify-expansion-plan.mjs --full
swift Scripts/verify-lineage-audit.swift
swift Scripts/verify-character-assets.swift Sources/SidekinApp/Resources/Characters
```

The expansion verifier checks catalog integration, ID and narrative uniqueness, tag requirements, five-stage completeness, progress-ledger integrity, poster mappings, final dimensions and alpha channels, review-sheet count, and the normalized asset hash. The combined character verifier adds exact file-set, binary uniqueness, occupancy, transparent-corner, and high-similarity gates across all 1,000 assets.

The audit is internal reproducibility and visual-QA evidence. It is not an independent external review, marketplace approval, production deployment, or evidence of real-user adoption.
