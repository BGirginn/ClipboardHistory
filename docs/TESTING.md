# Test and release matrix

No single layer is sufficient. A beta tag requires retained evidence from the exact release commit and exact arm64 artifact for every row below.

| Gate | Required evidence | Current local status (2026-08-01) |
|---|---|---|
| Swift build | arm64 Debug, Release, CommunityRelease; macOS 14 minimum; zero compiler/analyzer/linker diagnostics | All three configurations passed the `lipo`, `file`, `otool`, and minimum-OS gate; analyzer passed locally |
| Unit/integration | Model, pasteboard, storage, encryption, migration, lock lifecycle, search, stack, OCR/QR | 126 passed, 0 failed |
| Fuzz | 10,000+ deterministic hostile inputs plus malformed archive/media cases | 10,000-input deterministic test passed; expanded media corpus remains incomplete |
| Coverage | Every executable production Swift line, per file and aggregate, 100% | 73.14% (8,360/11,430) from merged unit/UI coverage; blocked |
| UI automation | Status item, shortcut, panel/menu tracking, keyboard, settings, lock, paste, drag/drop, import/export | 6 isolated ad-hoc-signed UI tests passed; Apple Development-signed full-flow coverage remains pending |
| Accessibility/visual | macOS 14/15/26, light/dark, high contrast, reduced motion/transparency, 200%, Turkish/English, VoiceOver/focus, small/multiple displays | Partial render and Turkish smoke evidence only; full matrix pending |
| Performance | Optimized arm64 Release, warm-up, 10 runs, p95 thresholds | Automated 5,000-item write/read/load/filter/panel-layout p95 gate passed |
| Sanitizers | ASan and TSan separately with `ENABLE_DEBUG_DYLIB=NO` and zero diagnostics | ASan 125 passed; TSan 125 passed; no warning or sanitizer diagnostic |
| Mutation | Pasteboard identity, retention, authenticated decryption, search, archive, lock capture, key rotation | 7 killed, 0 survived |
| Soak/Instruments | Eight hours; idle CPU <1%; RSS <75 MB; <10% post-warm-up growth; no crash/hang; SQLite integrity; Time Profiler/Leaks/Energy/Concurrency | Pending |
| Compatibility | arm64 on macOS 14, 15, and 26 | macOS 26.5 arm64 passed locally; macOS 14/15 and exact release-commit matrix evidence pending |
| Distribution | Stable certificate, provisioning profile, quarantined clean-user install, checksums, SPDX SBOM, Cask audit/install/upgrade/uninstall | `syft` 1.50.0 arm64 is installed; stable Community identity, matching Development profile, clean-machine evidence, tag, Release, and Cask are absent |

Run unit and UI coverage separately and merge their `.xccovreport`/`.xccovarchive` evidence:

```sh
scripts/run-coverage-suite.sh /private/tmp/ClipboardHistoryCoverage
```

The script uses unsigned unit tests and an ad-hoc-signed UI build with the empty Community entitlement file. UI launches use Debug-only switches for an isolated temporary database, named pasteboard, UserDefaults suite, and ephemeral test key. Release and CommunityRelease do not compile those switches.

The Apple Development-signed UI run is a separate gate. It requires an installed private key plus a provisioning profile that authorizes the Development build's `keychain-access-groups` entitlement:

```sh
scripts/verify-development-signing.sh
```

CI uses Apple-silicon `macos-14`, `macos-15`, and `macos-26` runners. The signed UI job remains opt-in on a protected interactive arm64 runner and cannot be counted as passing while skipped.
