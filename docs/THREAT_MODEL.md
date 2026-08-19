# Threat model

This model covers Sidekin 2.2's Electron runtime, local agent adapters, optional
image Workshop, Pet Packs, and packaged source-Beta artifacts.

## Protected assets

- User API key and optional paid image-generation authority
- Prompts, replies, code, tool output, projects, and full local paths
- Local growth state, task metadata, jobs, templates, and generated art
- Integrity of hooks, Pet Packs, runtime assets, application state, and updates
- User control of windows, click-through behavior, startup, and integrations

## Trust boundaries

```text
Codex / Claude Code hooks
        │ bounded lifecycle JSON
        ▼
trusted Electron main process ── operating-system app data / credential store
        │ narrow validated IPC
        ▼
sandboxed local renderers

trusted main process ── explicit confirmed request ── api.openai.com
Pet Pack ZIP ── hostile-input validation ── local template store
```

The renderer, hook input, imported archives, selected files, and API responses
are treated as untrusted. The main process and checked-in build scripts are
trusted only at the exact reviewed commit.

## Principal threats and mitigations

| Threat | Mitigation |
|---|---|
| Renderer compromise reaches Node or arbitrary IPC | Sandbox, context isolation, no Node integration, narrow preload API, exact sender URL checks, runtime argument validation |
| Remote content navigates or opens a privileged window | CSP, blocked navigation and popups, denied permission requests |
| Local configuration, session, asset, or reference path leaks to renderer or logs | Absolute paths remain in main; renderer receives standard labels, workspace basename, manifest-approved stage/recovery `sidekin-media://` identifiers, or a short-lived opaque reference token consumed on use; manifests, job JSON, and original references are not served |
| Hook captures prompt or code content | Provider-specific minimizer persists only lifecycle identifiers, time, state, and workspace basename |
| Sidekin deletes unrelated hooks | Namespaced install/remove logic and preservation tests |
| Untrusted Pet Pack escapes its directory or executes code | Data-only allowlist, traversal/absolute-path/duplicate rejection, expanded-size and image limits, SHA-256 verification |
| Corrupt or partial state destroys progress | Atomic local writes, known-good JSON backups, migration tests, bounded defaults, resumable raw-stage persistence, and interrupted template-install recovery |
| Background removal damages pink/purple subjects | Adaptive edge-connected fill instead of global color deletion; local preview/reprocess path |
| Duplicate or replayed events grant repeated growth | Provider/session/turn deduplication and bounded task history |
| Stale hook leaves permanent working state | Two-hour stale transition to interrupted plus user-clear action |
| Hidden network collection | No telemetry or maintainer backend; optional Workshop is a separate explicit request path |
| Oversized or malformed local/API input exhausts memory | File, manifest, archive, expanded-entry, hook-input, JSON, and streamed API-response limits; corrupt siblings are isolated |
| Supply-chain or packaged-file drift | Lockfile installs, pinned Actions, dependency audit, CodeQL, source/runtime hashes, and all-asset package re-hashing plus content/count/size checks |

## Residual risks

- A malicious local process running as the same user can read or modify many
  user-level files and hook configurations; Sidekin is not an OS security
  boundary.
- Electron, agent hook formats, image APIs, and operating-system credential
  implementations are upstream dependencies and can change.
- An imported reference can contain sensitive visual information even when its
  path is hidden; the user must review uploads before confirmation.
- Source-Beta ZIPs are not Developer ID/notarized on macOS and not Authenticode
  signed on Windows, so identity and tamper resistance depend on the reviewed
  commit, CI logs, and published SHA-256 evidence.
- Visual-content review and provenance records reduce but cannot eliminate all
  intellectual-property or cultural-symbol risks.

## Security regression gates

`npm run verify` exercises zero-warning linting, the sender boundary, retired
surfaces, lifecycle and migration invariants, backup recovery, hook
preservation, metadata minimization, archive/API abuse, asset hashes,
accessibility contracts, and a real Electron UI smoke path.
Native CI repeats verification and packaging on macOS and Windows.
