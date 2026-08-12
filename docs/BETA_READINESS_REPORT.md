# Historical beta readiness report

> Historical evidence only. This report applies to `v1.0.0-beta.1` and must not be used as evidence for the current stabilization candidate. See `STABILIZATION_BETA_READINESS.md` for the current worktree.

Date: 2026-08-01

Candidate: `v1.0.0-beta.1`

Decision: **approved as a public self-signed Community prerelease with the validation gaps below disclosed; not approved as a production/notarized release**

This report records local evidence gathered during beta preparation. Later targeted interaction fixes and the app icon received focused regression/build verification rather than a repeat of the entire suite at the owner's request. It is not external OS-matrix evidence.

## Preservation and scope

- Before implementation, the complete dirty repository including `.git` was copied to a sibling directory named `ClipboardHistory-backup-20260801-ZteHHj`; 301 files were compared with `diff -rq` and matched.
- The original worktree was not reset or discarded. Work continues on `beta/arm64-opt-in-lock` from starting commit `351fe22`.
- The product remains offline-only. Certificates, private keys, and provisioning profiles are forbidden from the repository.

## Implemented changes

- Every target configuration now uses minimum macOS 14 and `ARCHS=arm64`; legacy platform build/release paths were removed. Debug, Release, and CommunityRelease are checked with `lipo`, `file`, `otool`, and bundle metadata.
- Application lock is off by default and modelled as `disabled`, `unlocked`, or `locked`. Enabling/disabling and unlocking use Touch ID or the Mac login password through LocalAuthentication; no separate ClipboardHistory password or verifier exists.
- The numbered settings migration preserves existing automatic-lock users. Later launches start locked when enabled; manual, Mac-lock, and inactivity options relock the app.
- While locked, copy/restore/paste and history visibility are blocked. Recording can remain enabled with encrypted persistence or be consumed and dropped; Private Mode/pause takes precedence. Ask-before-saving sensitive content remains memory-only until unlock or expiry.
- AES-GCM history encryption remains independent from the UI lock. Keychain, authentication, storage, and archive errors fail closed without plaintext fallback.
- Debug, Release, and CommunityRelease now share one classic login-Keychain service and one empty source entitlement file. Apple Development Team, Data Protection Keychain, keychain access groups, and provisioning profiles were removed. The existing master-key service name was retained and its 32-byte value was confirmed readable through the classic login-Keychain query without logging the key.
- `ClipboardHistoryViewModel` is a 223-line main-actor façade and `StorageService` a 384-line actor façade. Extracted controller/repository, asset, migration, maintenance, recovery, and rotation facets are all below 500 lines. Static checks enforce 500 lines and one top-level type per production Swift file.
- English and Turkish String Catalog entries cover the new lock states, actions, explanations, and errors.
- Settings now offer persistent System/Light/Dark appearance. Reopening the menu-bar panel always returns to the main history instead of stale settings/detail/search state, and the one-shot ignore action is visually distinct from Private Mode with armed-state feedback.
- Panel context-menu coordination now protects the right-mouse-down to AppKit menu-tracking transition, so the first right click cannot be mistaken for an outside interaction while genuine outside clicks still close the panel.
- The checked-in CI workflow is arm64-only on GitHub's macOS 14, 15, and 26 runners, but repository GitHub Actions are disabled by owner request. Equivalent architecture, sanitizer, performance, mutation, coverage, and UI gates run locally.
- Artifact tooling requires exact arm64 output and names ZIP/DMG/SBOM files `ClipboardHistory-1.0.0-beta.1-arm64.*`. The documented Cask requires Sonoma and arm64.

## Current local evidence

| Check | Result |
|---|---|
| Unit/integration/benchmark suite | 204 current tests covered by the unit/integration and optimized benchmark gates, 0 failed |
| UI suite | 7 passed, 0 failed with isolated ad-hoc production entitlements |
| Merged production line coverage | 100%, 11,880/11,880 executable lines |
| Per-file 100% coverage gate | Passed for every production Swift file; no production source exclusion |
| Debug/Release/CommunityRelease | Passed; exact `arm64`; minimum macOS 14 |
| ASan | 203 eligible tests passed; no compiler/linker/sanitizer diagnostic |
| TSan | 203 eligible tests passed with `ENABLE_DEBUG_DYLIB=NO`; no duplicate-rpath or sanitizer diagnostic |
| Deterministic fuzz | 10,000 hostile validation inputs plus 512 malformed media corpus cases passed |
| Critical mutation set | 7 killed, 0 survived |
| Optimized performance | Warm-up plus 20-repeat 5,000-item p95 assertions passed |
| Idle resource smoke | CommunityRelease after 30-second warm-up: 10/10 CPU samples at 0.0%, maximum RSS 44,400 KB, SQLite `integrity_check=ok` |
| Localization/static/source structure | Passed |
| Accountless signing | Stable `ClipboardHistory Community Beta` identity installed; SHA-256 `13:19:E8:8B:23:2F:B0:F1:70:A5:DE:8B:A8:32:D3:58:72:E1:C9:5C:D0:3D:A9:59:90:23:47:62:3D:ED:46:CC` |
| Signed CommunityRelease | `1.0.0 (10001)`, beta label `1.0.0-beta.1`, exact arm64, empty final entitlements, hardened runtime, designated requirement verified; launched and quit cleanly |

The merged coverage result is retained locally as `Combined.xccovreport` alongside its unit and UI `.xcresult` bundles. Release evidence paths are working-session artifacts and are not committed into the source repository.

## Known beta validation gaps

1. The seven isolated UI tests cover the automated action matrix, but the self-signed Debug app did not complete Xcode's `XCUIApplication.launch()` handshake. The final self-signed status-item, Accessibility paste, lock settings, drag/drop, import/export, collection/stack, multi-display, and failure-state flows still require a clean-user manual run.
2. Full VoiceOver/focus, high contrast, Reduce Motion/Transparency, 200% scaling, light/dark, both locales, small-screen, multi-display, and macOS-version evidence is absent.
3. Actual panel-visible timing, scrolling, large-media stress, Instruments, and the eight-hour soak/growth run remain incomplete. The short idle CPU/RSS and SQLite integrity smoke passes.
4. Only macOS 26.5 arm64 executed locally. Repository Actions are disabled, so macOS 14/15/26 evidence from the exact clean release commit requires an explicitly authorized external run.
5. The self-signed identity has not yet been exported from Keychain Access as an encrypted `.p12` backup stored outside the repository.
6. A quarantined temporary artifact copy was rejected by Gatekeeper as expected for an unnotarized self-signed app. A separate clean-user/VM Open Anyway run remains unrecorded; the publication-time checksum and Homebrew lifecycle checks are recorded below.

The owner explicitly authorized a public beta release with these gaps disclosed. This decision does not convert the Community build into a notarized production release and does not waive the missing external matrix for a later stable release.

## Publication evidence

- Annotated tag `v1.0.0-beta.1` points to clean release commit `fad51547ceec3f68ba82734dbd699645bcfa985e`.
- The public GitHub prerelease contains the signed arm64 ZIP and DMG, SPDX SBOM, checksum manifest, designated requirement, and signing-certificate fingerprint.
- The public `BGirginn/homebrew-tap` repository publishes `Casks/clipboardhistory.rb` with exact ZIP SHA-256 `8d2bf2a7312e3eec6a915c92507110d2e4a0bceb6b2e1cb0108d2dffcdd0576f`, `depends_on arch: :arm64`, and `depends_on macos: :sonoma`.
- Homebrew style and strict Cask audit passed. The central `homebrew/cask` new-cask eligibility audit remains intentionally inapplicable because this is a self-signed GitHub prerelease in a personal tap and does not meet official notability/notarization rules.
- Homebrew fetched the public ZIP with the published checksum, retained quarantine, installed into an isolated app directory, and launched the exact `1.0.0 (10001)` arm64 app. Normal uninstall removed the staged app while preserving Application Support and SQLite `integrity_check=ok`.
- GitHub Actions are disabled at repository level for both `BGirginn/ClipboardHistory` and `BGirginn/homebrew-tap` by owner instruction.
