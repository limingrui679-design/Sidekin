# Sidekin Pet Pack SDK

Pet Packs are data-only `.sidekinpet` archives for sharing one custom lineage. They never contain JavaScript, native code, hooks, API keys, or machine-specific paths.

## Quick start

```bash
npm run pet-pack -- init ./my-sidekin
# Replace the generated metadata and add stage-01.png.
npm run pet-pack -- validate ./my-sidekin
npm run pet-pack -- pack ./my-sidekin ./my-sidekin.sidekinpet
npm run pet-pack -- unpack ./my-sidekin.sidekinpet ./review-copy
```

The CLI refuses undeclared files, duplicate ZIP entries, traversal paths, corrupt images, oversized content, opaque stage art, stale hashes, unsupported or future Sidekin versions, unsupported motion profiles, and non-monotonic growth thresholds. `unpack` will not overwrite a non-empty directory.

## Manifest

Every pack contains `template.json`, one to eight transparent PNG stage images, and an optional PNG reference. The current format is `sidekin.pet-pack`, schema `2`.

Required identity fields are `id`, `name`, `author`, `license`, `motionProfile`, `basePrompt`, and `artDirection`. Each stage has a zero-based contiguous `index`, a unique safe `assetFileName`, a `name`, a `prompt`, and a monotonic `experienceThreshold`. The `pack` command writes SHA-256 `contentHashes` for every declared image.

Available motion profiles:

`agile`, `bouncing`, `buoyant`, `flowing`, `gliding`, `heavy`, `marching`, `mechanical`, `orbiting`, `poised`, `prowling`, `pulsing`, `rolling`, `rooted`, `serpentine`, `skittering`, `spectral`, `swarming`, `swimming`, `winged`.

## Art contract

- Full character inside frame with transparent background.
- PNG, 32–4096 px per side, at most 20 MiB per image; stage art must contain an alpha channel, while an optional reference may be opaque.
- At most 96 MiB packed/expanded, with a `template.json` no larger than 1 MiB.
- A stable identity anchor across every stage; no unexplained species replacement.
- A materially distinct silhouette, anatomy, pose, or ability at every growth threshold.
- Readable at roughly 235 px desktop-pet size.
- You must own or have permission to distribute every asset and state its license accurately.

Schema-1 packs made by Sidekin 2.1 are migrated locally on import. New exports always use schema 2 with provenance and content hashes.
