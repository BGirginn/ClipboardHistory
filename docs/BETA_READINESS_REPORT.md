# Beta readiness report

Date: 2026-08-01

Candidate: `v1.0.0-beta.1`

Decision: **blocked; do not tag, publish, or create the Cask**

This report records local evidence for the clean `beta/arm64-opt-in-lock` branch tip. It is not signed-distribution or external OS-matrix evidence and becomes stale after any source change.

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
- CI is arm64-only on GitHub's macOS 14, 15, and 26 runners. Separate sanitizer, performance, mutation, coverage, architecture, analyzer, and protected signed-UI jobs exist.
- Artifact tooling requires exact arm64 output and names ZIP/DMG/SBOM files `ClipboardHistory-1.0.0-beta.1-arm64.*`. The documented Cask requires Sonoma and arm64.

## Current local evidence

| Check | Result |
|---|---|
| Unit/integration suite | 126 passed, 0 failed |
| UI suite | 6 passed, 0 failed with isolated ad-hoc production entitlements |
| Merged production line coverage | Previous source state: 73.1409%, 8,360/11,430 executable lines; regeneration required |
| Per-file 100% coverage gate | Failed as designed; no production source exclusion |
| Debug/Release/CommunityRelease | Passed; exact `arm64`; minimum macOS 14 |
| ASan | 125 passed; no compiler/linker/sanitizer diagnostic |
| TSan | 125 passed with `ENABLE_DEBUG_DYLIB=NO`; no duplicate-rpath or sanitizer diagnostic |
| Deterministic fuzz | 10,000 hostile inputs passed; expanded media corpus pending |
| Critical mutation set | 7 killed, 0 survived |
| Optimized performance | Warm-up plus 10-repeat 5,000-item p95 assertions passed |
| Localization/static/source structure | Passed |
| Accountless signing | Stable `ClipboardHistory Community Beta` identity installed; SHA-256 `13:19:E8:8B:23:2F:B0:F1:70:A5:DE:8B:A8:32:D3:58:72:E1:C9:5C:D0:3D:A9:59:90:23:47:62:3D:ED:46:CC` |
| Signed CommunityRelease | `1.0.0 (10001)`, beta label `1.0.0-beta.1`, exact arm64, empty final entitlements, hardened runtime, designated requirement verified; launched and quit cleanly |

The previous coverage evidence under `.build/CoverageAfterAdapters` predates the signing/Keychain source change and is not current release evidence. The current unit result is `/private/tmp/ClipboardHistorySelfSignedUnit2.xcresult`; the current isolated UI result is `/private/tmp/ClipboardHistoryAdHocUIFinal.xcresult`. These paths are local working-session evidence and are not committed release artifacts.

## Remaining release blockers

1. The current source coverage merge has not been regenerated and the previous value was only 73.14%, not the mandatory 100%. Uncovered code remains in system integrations, error paths, Quick Look, drag providers, archive/mutation/privacy orchestration, recovery states, media rows, and SwiftUI action branches.
2. The six UI tests do not cover the complete protected self-signed status-item, Accessibility paste, lock settings, drag/drop, import/export, collection/stack, multi-display, and failure-state matrix.
3. Full VoiceOver/focus, high contrast, Reduce Motion/Transparency, 200% scaling, light/dark, both locales, small-screen, multi-display, and macOS-version evidence is absent.
4. Idle CPU, RSS, actual panel-visible timing, scrolling, large-media stress, Instruments, and the eight-hour soak remain incomplete.
5. Only macOS 26.5 arm64 executed locally. macOS 14/15/26 evidence from the exact clean release commit remains required.
6. The self-signed identity has not yet been exported from Keychain Access as an encrypted `.p12` backup stored outside the repository.
7. No quarantined clean-user/VM Gatekeeper test, checksum comparison, public-repository transition, tag, GitHub Release, or Homebrew Cask audit/install lifecycle exists.

Because these gates are mandatory, the repository was not made public and no tag, GitHub Release, artifact, tap repository, or Cask was created.
