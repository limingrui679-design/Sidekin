# CainiaoPet Distribution Guide

> CainiaoPet is currently maintained as a GitHub source project and local Beta. There is no plan to distribute a signed application directly to general users. Developer ID signing, notarization, and Gatekeeper acceptance are therefore not current completion requirements. This page is retained only for a future change in distribution scope.

## Keep the Two Package Types Distinct

- `./Scripts/package-release.sh` creates an ad-hoc signed package for local testing. It includes complete checks, resource hashes, and a clean ZIP, but it does not include Developer ID signing or Apple notarization.
- `./Scripts/release-public.sh` is the guarded process for a future direct public distribution. It requires a clean Git commit, Developer ID signing, Hardened Runtime, notarization, ticket stapling, and Gatekeeper acceptance.

Never label an ad-hoc package as Apple-verified or as a public distribution build.

## Optional First-Time Setup

Complete these steps only if the distribution target changes:

1. Create and install a `Developer ID Application` certificate through the publisher's Apple Developer account.
2. Register the reverse-domain Bundle ID used for the project.
3. Store notarization credentials in the current user's Keychain, never in the repository:

```bash
xcrun notarytool store-credentials "CainiaoPet-Notary"
```

4. Commit the source and confirm that the working tree contains no untracked or uncommitted files.

## Optional Public Distribution

The publisher must supply these values from their own Apple Developer account:

```bash
export CAINIAOPET_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export CAINIAOPET_NOTARY_PROFILE="CainiaoPet-Notary"
export CAINIAOPET_BUNDLE_ID="com.example.cainiaopet"
./Scripts/release-public.sh
```

The script performs the following sequence:

1. Runs source, API mock, asset, Debug, and Release checks.
2. Signs the bridge helper, main executable, and application bundle separately with Hardened Runtime and a secure timestamp.
3. Creates an upload ZIP without `__MACOSX`, `.DS_Store`, or AppleDouble entries.
4. Submits the package with `notarytool` and waits for Apple's result.
5. Staples the notarization ticket to the application and validates the ticket.
6. Rebuilds the final ZIP, release manifest, and SHA-256 file from the stapled application.
7. Runs Gatekeeper acceptance with `spctl` and re-verifies the archived application.

Only after the script reports that every public-distribution gate passed should the binary be offered as a GitHub Release intended for direct download and execution by general users. The current source project and CI build-verification workflow do not require this process.

## Distribution Files

```text
artifacts/CainiaoPet-macOS-arm64.zip
artifacts/CainiaoPet-macOS-arm64.RELEASE.json
artifacts/CainiaoPet-macOS-arm64.zip.sha256
```

Before upload, keep the version tag aligned with `Support/Info.plist`, including the version and build number, and identify the same source commit in the release notes. Do not upload the unpacked `artifacts/CainiaoPet.app` directory.
