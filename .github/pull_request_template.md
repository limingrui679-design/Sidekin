## Summary

Describe the user-visible outcome and why the change belongs in Sidekin.

## Verification

- [ ] `npm run verify`
- [ ] I added or updated tests for changed behavior or explained why none apply.
- [ ] I tested the affected platform or clearly identified the native CI gate.
- [ ] Screenshots use isolated synthetic data and contain no private paths or IDs.

## Safety and compatibility

- [ ] No API key, prompt, reply, proprietary code, local app data, or paid API response is included.
- [ ] Renderer sandboxing, IPC validation, hook preservation, and local-first metadata boundaries remain intact.
- [ ] Persistent-data and Pet Pack changes include backward-compatible migration coverage.
- [ ] UI changes support keyboard focus, high contrast, and reduced motion where applicable.
- [ ] New visual assets identify creator, provenance, and rights status.
- [ ] Package or runtime-asset growth is measured and remains within documented budgets.

## Distribution boundary

This pull request changes reviewable source. It does not by itself create a
signed, notarized, Authenticode-signed, or publicly released consumer build.
