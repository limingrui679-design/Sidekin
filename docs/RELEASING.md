# Sidekin source build and CI guide

Sidekin is a GitHub source project, not a signed public application release. The supported workflow builds one shared runtime and verifies it on native macOS and Windows GitHub Actions runners.

## Build from source

The optimized 1,000-form runtime catalog is stored directly in Git; Git LFS is not required.

```bash
git clone https://github.com/limingrui679-design/Sidekin.git
cd Sidekin
npm ci
npm run verify
npm start
```

Create current-platform output:

```bash
npm run package   # unpacked application
npm run make      # ZIP plus SHA-256 and package report
```

Generated output is written under ignored `out/` and can be rebuilt. Packaging enforces 1,000 runtime forms, 200 thumbnails, required manifests/resources, all 1,200 packaged asset hashes, archive integrity, and size budgets.

## Native CI matrix

`.github/workflows/desktop.yml` runs for pull requests and pushes to `main`:

- `macos-latest`: shared verification, real Electron E2E, macOS packaging, ad-hoc signature verification, ZIP inspection
- `windows-latest`: shared verification, real Electron E2E, Windows packaging and ZIP inspection

Successful jobs upload `out/make/` as temporary workflow artifacts. The workflow does not create a GitHub Release or publish an installer.

## Full-resolution art

Main ships approximately 106 MiB of optimized catalog media. The full PNG authoring corpus is pinned to commit `0fca27df3ae9e4e32ab37651efb1a8f756912ffb`; `archive/full-png-corpus-v2.1` is a convenience pointer, not the integrity boundary. See [`ART_ARCHIVE.md`](ART_ARCHIVE.md) for provenance and rebuild commands.

## Version checklist

1. Update `package.json`, lockfile, README status, and completion audit.
2. Run `npm ci`, `npm run verify`, `npm run make`, and `npm audit --omit=dev`.
3. Inspect the package report, ZIP SHA-256, archive entry list, and app size.
4. Push a review branch and wait for both native matrix jobs and CodeQL.
5. Merge only after the exact commit is green and repository links render from a clean clone.

## Signing boundary

The macOS source package is ad-hoc signed so the locally built bundle can be inspected. It is not Developer ID signed or notarized. Windows output is not Authenticode signed. These are expected source-Beta properties and must not be described as Apple-verified, Microsoft-verified, or consumer-ready distribution.

If project scope later changes to direct binary distribution, signing identities, Apple notarization, Windows reputation, update channels, and release provenance require a separate reviewed workflow. They are intentionally outside the current goal.
