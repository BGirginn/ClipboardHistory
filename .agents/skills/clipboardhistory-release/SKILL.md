---
name: clipboardhistory-release
description: Validate ClipboardHistory build, tests, static quality, sanitizers, architecture, performance, signing, community artifact, release evidence, and release documentation. Trigger for release readiness, beta/stable gates, packaging, signing, CI changes, or claims that a commit is ready to ship.
---

# Release Validation Workflow

Read:
- `docs/TESTING.md`
- `docs/DISTRIBUTION.md`
- `docs/KNOWN_LIMITATIONS.md`
- `docs/PRIVACY_AND_THREAT_MODEL.md`
- current release notes/readiness report,
- `.github/workflows/quality.yml`,
- release scripts.

## Evidence rule

A script existing is not evidence that it passed.
Historical documentation is not proof for the current commit.
A unit test with stubs is not native-platform acceptance.

Separate every result into:
1. executed and passed on this commit,
2. historical evidence only,
3. not run / environment unavailable,
4. failed or blocked.

## Core gates

Use the repository-provided scripts rather than inventing substitute commands:

```zsh
scripts/verify-static-quality.sh
scripts/run-development-tests.sh
scripts/verify-arm64-builds.sh
scripts/verify-sanitizers.sh
scripts/verify-performance.sh
scripts/run-critical-mutations.sh
```

For coverage/release evidence as appropriate:

```zsh
scripts/run-coverage-suite.sh
scripts/verify-coverage.sh
scripts/release-gate.sh
```

Use the documented Community artifact builder for Community releases rather than ad-hoc packaging.

## Platform matrix

Do not call stable/release-ready based only on one local macOS version if the documented release contract requires a broader matrix.

Track separately:
- macOS 14,
- macOS 15,
- macOS 26,
- arm64 architecture,
- signed interactive behavior,
- UI automation limitations,
- manual Accessibility/paste behavior,
- Keychain/login session,
- CoreAudio,
- IOKit/HID/sensors,
- Chromium/Safari integration,
- multi-display/notch interaction.

## Documentation

Version/build numbers, signing mode, notarization status, certificate fingerprint requirements, known limitations, checksums, and SPDX metadata must agree with the produced artifact.

Never describe a self-signed Community build as Apple-notarized or Developer ID production distribution.

## Output

Blockers first, then:
- automated gates,
- platform/manual gates,
- documentation consistency,
- final go/no-go with evidence.
