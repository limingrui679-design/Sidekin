# Privacy model

Sidekin is local-first. The default companion loop does not upload prompts,
agent replies, code, tool output, project files, care data, or task history.

## Data inventory

| Data | Stored | Purpose | Network behavior |
|---|---|---|---|
| Care, XP, stage, streak, temperament, journal | Local app-data directory | Persistent growth | Never sent by Sidekin |
| Selected lineage and settings | Local app-data directory | Restore the UI and companion | Never sent by Sidekin |
| Provider, lifecycle state, time, session/turn ID, workspace basename | Local app-data directory; bounded history | Live task cards and deduplication | Never sent by Sidekin |
| Prompts, replies, code, tool output, full workspace path | Not persisted by Sidekin | Not required | Never sent by Sidekin |
| Pet Packs, templates, jobs, raw and processed stages | Local app-data directory | Creation and recovery | Never sent unless a stored stage is explicitly used as a confirmed image reference |
| OpenAI API key | Encrypted local credential store | Optional Workshop requests | Sent only to `api.openai.com` during a confirmed request |
| Confirmed generation description and reference image | Not used by the care loop | Optional image generation/editing | Sent to OpenAI only after explicit confirmation |

The app has no telemetry, advertising identifier, crash-report uploader, or
maintainer-operated backend.

Absolute agent-configuration, session, reference-image, and application-data
paths remain in the trusted main process. Renderers receive standard path
labels, workspace basenames, short-lived opaque reference tokens, and logical
`sidekin-media://` URLs for explicitly allowlisted pet images.

Public renderer state is an explicit allowlist. It excludes generation and
stage prompts, reference paths, job manifests, raw session IDs, internal event
deduplication records, and template recovery metadata.

## Retention and deletion

The growth journal and activity feed are bounded by the lifecycle engine.
Reference-selection tokens expire after 30 minutes and are consumed by a
request. The chosen source path and original file name are discarded after a
bounded normalized copy is placed in the local recovery job. The hook event
inbox is compacted at 2 MiB; journal, activity, deduplication, and fallback
reads are bounded. JSON state keeps one known-good local backup for recovery.

Uninstalling the executable does not automatically delete user-created data.
To reset Sidekin, quit it and remove the Sidekin application-data directory:

```text
macOS:   ~/Library/Application Support/Sidekin/
Windows: %APPDATA%\Sidekin\
```

Removing that directory permanently deletes local growth, settings, jobs, and
templates. Back up any Pet Packs or generated stages you want to keep first.
Remove Sidekin's entries from the operating-system credential store separately
if a complete credential reset is required.

## Agent hooks

Sidekin installs only namespaced command hooks selected in Settings and preserves
unrelated hooks. Removing an integration deletes only Sidekin-owned handlers.
Codex may require explicit hook review through `/hooks`. The optional Codex
session fallback is off by default because the transcript format is unstable.

## User responsibility

Before an optional image request, review the confirmation summary and the
provider's current API terms, data controls, and prices. Use only references you
are authorized to upload. Do not place secrets in generation descriptions.
