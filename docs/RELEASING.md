# Sidekin Build and CI Guide

Sidekin is a GitHub source project, not a signed public application release. The supported workflow builds the shared runtime locally and verifies it on native macOS and Windows GitHub Actions runners.

## Build from Source

Git LFS is required for the 1,000 built-in character assets.

```bash
git lfs install
git clone https://github.com/limingrui679-design/Sidekin.git
cd Sidekin
npm ci
npm run verify
npm start
```

Create platform output for the current computer:

```bash
npm run package   # unpacked application
npm run make      # ZIP for the current macOS or Windows computer
```

The packaging script writes generated files under `out/`. They are ignored by Git and may be deleted and rebuilt at any time.

## Native CI Matrix

`.github/workflows/desktop.yml` runs on pushes and pull requests:

- `macos-latest`: catalog and lineage audit, shared verification, macOS packaging
- `windows-latest`: shared verification and Windows ZIP packaging

Both jobs also verify the completed 100-lineage expansion ledger and all 500 integrated expansion assets before packaging.

Each successful job uploads its `out/make/` files as a workflow artifact. The workflow does not create a GitHub Release or publish an installer.

## Signing Boundary

The macOS package is ad-hoc signed only so the locally built bundle can be launched and inspected. It is not Developer ID signed or notarized. The Windows package is not Authenticode signed. These are expected properties of the source-Beta workflow and must not be described as Apple-verified, Microsoft-verified, or consumer-ready distribution.

If the project later changes scope to direct public binary distribution, signing identities, notarization, installer reputation, update channels, and release provenance require a separate reviewed workflow. They are intentionally outside the current GitHub-source goal.

## Historical Tools

The older Swift package and macOS release scripts remain as provenance and art-pipeline references. They do not define the Sidekin 2.0 runtime or the cross-platform packaging path. Use the npm commands above for current builds.
