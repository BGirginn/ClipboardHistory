# Test and release matrix

No single layer is sufficient. A beta tag requires retained evidence from the exact release commit and exact arm64 artifact for every row below.

| Gate | Required evidence | Current local status (2026-08-01) |
|---|---|---|
| Swift build | arm64 Debug, Release, CommunityRelease; macOS 14 minimum; zero compiler/analyzer/linker diagnostics | All three configurations passed the `lipo`, `file`, `otool`, and minimum-OS gate; analyzer passed locally |
| Unit/integration | Model, pasteboard, storage, encryption, migration, lock lifecycle, search, stack, OCR/QR | 201 current tests passed across the unit/integration and optimized benchmark gates; 0 failed |
| Fuzz | 10,000+ deterministic hostile inputs plus malformed archive/media cases | 10,000 hostile archive/HTML/path inputs and 512 malformed PNG/JPEG/GIF/TIFF/BMP/HEIC/PDF/RTF corpus cases passed |
| Coverage | Every executable production Swift line, per file and aggregate, 100% | Passed: 11,714/11,714 executable production lines and every production Swift file at 100% |
| UI automation | Status item, shortcut, panel/menu tracking, keyboard, settings, lock, paste, drag/drop, import/export | 7 isolated ad-hoc-signed UI tests passed. A self-signed Debug attempt remained in `XCUIApplication.launch()` for more than 10 minutes despite valid signatures and test entitlements; manual signed-app coverage remains pending |
| Accessibility/visual | macOS 14/15/26, light/dark, high contrast, reduced motion/transparency, 200%, Turkish/English, VoiceOver/focus, small/multiple displays | Partial render and Turkish smoke evidence only; full matrix pending |
| Performance | Optimized arm64 Release, warm-up, 10 runs, p95 thresholds | Automated 5,000-item write/read/load/filter/panel-layout p95 gate passed |
| Sanitizers | ASan and TSan separately with `ENABLE_DEBUG_DYLIB=NO` and zero diagnostics | ASan 200 passed; TSan 200 passed; the optimized benchmark is intentionally separate; no warning or sanitizer diagnostic |
| Mutation | Pasteboard identity, retention, authenticated decryption, search, archive, lock capture, key rotation | 7 killed, 0 survived |
| Soak/Instruments | Eight hours; idle CPU <1%; RSS <75 MB; <10% post-warm-up growth; no crash/hang; SQLite integrity; Time Profiler/Leaks/Energy/Concurrency | Pending |
| Compatibility | arm64 on macOS 14, 15, and 26 | macOS 26.5 arm64 passed locally; macOS 14/15 and exact release-commit matrix evidence pending |
| Distribution | Stable self-signed certificate and encrypted backup, quarantined clean-user install, checksums, SPDX SBOM, Cask audit/install/upgrade/uninstall | Stable Community identity and `syft` 1.50.0 arm64 are installed; signed ZIP/DMG, checksums, SPDX SBOM, requirement, and fingerprint were produced and verified locally. Encrypted `.p12` backup, clean-machine evidence, tag, Release, and Cask are absent |

Run unit and UI coverage separately and merge their `.xccovreport`/`.xccovarchive` evidence:

```sh
scripts/run-coverage-suite.sh /private/tmp/ClipboardHistoryCoverage
```

The script uses unsigned unit tests and an ad-hoc-signed UI build with the empty production entitlement file. UI launches use Debug-only switches for an isolated temporary database, named pasteboard, UserDefaults suite, and ephemeral test key. Release and CommunityRelease do not compile those switches.

The self-signed UI attempt is a separate diagnostic. It requires the stable Community identity but no Apple account or provisioning profile:

```sh
scripts/verify-community-signing.sh
```

CI uses Apple-silicon `macos-14`, `macos-15`, and `macos-26` runners. The signed UI job remains opt-in on a protected interactive arm64 runner. The current macOS 26.5 attempt did not get beyond Xcode's application-launch handshake, so this job cannot be counted as passing and does not replace manual testing of the final self-signed artifact.
