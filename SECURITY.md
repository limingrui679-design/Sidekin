# Security Policy

## Supported release

Security fixes target the latest `2.2.0-beta.x` source Beta. Older beta tags are
retained for provenance and should not be treated as supported builds.

## Report a vulnerability

Please use the repository's private
[GitHub security advisory form](https://github.com/limingrui679-design/Sidekin/security/advisories/new).
Do not open a public issue for an unpatched vulnerability and do not include
API keys, local Sidekin data, Codex logs, or personal information in a report.

Include the affected commit or tag, operating system, reproduction steps,
expected behavior, observed behavior, and the smallest safe proof of concept.

## Product boundary

Sidekin is a source Beta. Its macOS CI archive is ad-hoc signed and not
notarized; its Windows CI archive is not Authenticode signed. These expected
properties are not security vulnerabilities. Reports about renderer isolation,
local file handling, credential storage, archive integrity, dependency risk, or
unexpected network access are in scope.

## Response expectations

The maintainer will acknowledge a complete private report within seven days,
provide an initial severity assessment when reproduction is possible, and keep
the reporter informed before any coordinated disclosure. Timelines can vary for
reports that depend on an upstream agent, Electron, operating-system, or API fix.
