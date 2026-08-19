# Contributing to Sidekin

Thank you for improving Sidekin. The most useful contributions make the live
companion more reliable, private, accessible, expressive, or easier to verify.

## Before opening a pull request

1. Search existing issues and pull requests.
2. Use a feature issue before a large behavior, data-format, or art-direction
   change so scope can be agreed before implementation.
3. For security vulnerabilities, follow `SECURITY.md` and report privately.
4. Never include API keys, prompts, code from private projects, personal paths,
   paid API responses, or user application data in an issue, fixture, or log.

## Development setup

Sidekin supports Node.js 22.12+ (within the Node 22 LTS line) on macOS 13+ and Windows 10/11.

```bash
git clone https://github.com/limingrui679-design/Sidekin.git
cd Sidekin
npm ci
npm run verify
npm start
```

Run a narrower check while iterating:

```bash
npm run typecheck
npm run lint
npm test
npm run assets:verify
npm run e2e
```

## Pull-request contract

- Keep one focused change per pull request and describe user-visible behavior.
- Add or update deterministic tests for lifecycle, migration, IPC, archive, or
  recovery changes.
- Preserve sandboxing, context isolation, exact sender validation, permission
  denial, reference-token isolation, and local metadata minimization.
- Keep persistent-state migrations backward compatible and idempotent.
- Keep agent hook installation independent and preserve unrelated user hooks.
- Respect reduced motion, keyboard focus, readable labels, and high contrast.
- Do not weaken runtime-asset or package size budgets without measured evidence.
- Confirm that `npm run verify` passes before requesting review.

## Art and Pet Packs

Built-in art must remain non-infringing, suitable for all audiences, readable at
desktop-pet size, and continuous across every evolution stage. New visual assets
must include their creator, provenance, and rights status in the pull request.
Do not add material copied from a commercial game, franchise, artist, or model
output whose reuse rights are unclear.

Use the data-only Pet Pack format for external lineages. See
`docs/PET_PACK_SDK.md`; executable code is intentionally forbidden in packs.

The accepted full-resolution corpus is pinned to the Git commit recorded in
`docs/ART_ARCHIVE.md`; `archive/full-png-corpus-v2.1` is a convenience pointer.
Main contains optimized runtime WebP files and a hash/provenance manifest.
Follow the archive guide before rebuilding assets.

## Licensing boundary

Sidekin is proprietary and all rights are reserved. Viewing the source or
submitting a pull request does not change the repository license. Contributors
must own or be authorized to submit their code and assets. If additional written
licensing terms are needed for a contribution, the maintainer will resolve them
before merge.
