# Test and release matrix

No single layer is sufficient. A beta tag requires retained evidence from the exact release commit and exact arm64 artifact for every row below.

| Gate | Required evidence | Current local status (2026-08-01) |
|---|---|---|
| Swift build | arm64 Debug, Release, CommunityRelease; macOS 14 minimum; zero compiler/analyzer/linker diagnostics | All three configurations passed the `lipo`, `file`, `otool`, and minimum-OS gate; analyzer passed locally |
| Unit/integration | Model, pasteboard, storage, encryption, migration, lock lifecycle, search, stack, OCR/QR | 204 current tests passed across the unit/integration and optimized benchmark gates; 0 failed |
| Fuzz | 10,000+ deterministic hostile inputs plus malformed archive/media cases | 10,000 hostile archive/HTML/path inputs and 512 malformed PNG/JPEG/GIF/TIFF/BMP/HEIC/PDF/RTF corpus cases passed |
| Coverage | Every executable production Swift line, per file and aggregate, 100% | Passed: 11,880/11,880 executable production lines and every production Swift file at 100% |
| UI automation | Status item, shortcut, panel/menu tracking, keyboard, settings, lock, paste, drag/drop, import/export | 7 isolated ad-hoc-signed UI tests passed. A self-signed Debug attempt remained in `XCUIApplication.launch()` for more than 10 minutes despite valid signatures and test entitlements; manual signed-app coverage remains pending |
| Accessibility/visual | macOS 14/15/26, light/dark, high contrast, reduced motion/transparency, 200%, Turkish/English, VoiceOver/focus, small/multiple displays | Partial render and Turkish smoke evidence only; full matrix pending |
| Performance | Optimized arm64 Release, warm-up, 10+ runs, p95 thresholds | Automated 5,000-item write/read/load/filter/panel-layout p95 gate passed with 20 repetitions; 10-sample idle smoke passed at 0.0% median CPU and 44,400 KB maximum RSS |
| Sanitizers | ASan and TSan separately with `ENABLE_DEBUG_DYLIB=NO` and zero diagnostics | ASan 203 passed; TSan 203 passed; the optimized benchmark is intentionally separate; no warning or sanitizer diagnostic |
| Mutation | Pasteboard identity, retention, authenticated decryption, search, archive, lock capture, key rotation | 7 killed, 0 survived |
| Soak/Instruments | Eight hours; idle CPU <1%; RSS <75 MB; <10% post-warm-up growth; no crash/hang; SQLite integrity; Time Profiler/Leaks/Energy/Concurrency | Short CommunityRelease idle CPU/RSS and SQLite integrity smoke passed; eight-hour growth, crash/hang, and Instruments evidence remain pending |
| Compatibility | arm64 on macOS 14, 15, and 26 | macOS 26.5 arm64 passed locally; macOS 14/15 and exact release-commit matrix evidence pending |
| Distribution | Stable self-signed certificate and encrypted backup, quarantined clean-user install, checksums, SPDX SBOM, Cask audit/install/upgrade/uninstall | Stable Community identity and `syft` 1.50.0 arm64 are installed; signed ZIP/DMG, checksums, SPDX SBOM, requirement, and fingerprint were produced and verified locally. Encrypted `.p12` backup, clean-machine evidence, tag, Release, and Cask are absent |

For normal feature work, use the bounded development-test cache instead of a
new `-derivedDataPath` for every run:

```sh
scripts/run-development-tests.sh
scripts/run-development-tests.sh ClipboardHistoryTests/PasteStackTests
scripts/run-development-tests.sh --clean
```

The script reuses `.build/DevelopmentTests`, replaces the previous result
bundle, and enforces a 2 GiB cache limit before and after each run. Xcode's
default DerivedData is also reusable; avoid UUID-based DerivedData paths for
routine testing.

The shared Xcode scheme runs the repository's artifact maintenance before and
after builds. It removes only recognized, rebuildable ClipboardHistory test and
build paths. The automatic policy removes temporary artifacts older than 24
hours, trims recognized temporary output above 2 GiB after a 30-minute safety
window, removes a development cache unused for seven days or larger than 2 GiB,
and trims ClipboardHistory's Xcode DerivedData above 4 GiB or after seven days.
Paths mentioned by a running process are kept. Source snapshots, release
artifacts, `ClipboardHistoryUI`, application data, and other projects' Xcode
data are outside the deletion rules.

Inspect or run the same maintenance manually:

```sh
scripts/cleanup-build-artifacts.sh --dry-run
scripts/cleanup-build-artifacts.sh --prune
scripts/cleanup-build-artifacts.sh --clean
```

`--dry-run` is the default and does not delete anything. `--prune` applies the
age and size policy. `--clean` immediately removes only the recognized
rebuildable artifacts and is intended for an explicit full cache reset. A
failed or cancelled build is picked up by the next scheme pre-action even when
its post-action could not run.

Run unit and UI coverage separately and merge their `.xccovreport`/`.xccovarchive` evidence:

```sh
scripts/run-coverage-suite.sh /private/tmp/ClipboardHistoryCoverage
```

The script uses unsigned unit tests and an ad-hoc-signed UI build with the empty production entitlement file. UI launches use Debug-only switches for an isolated temporary database, named pasteboard, UserDefaults suite, and ephemeral test key. Release and CommunityRelease do not compile those switches.

The suite retains compact unit/UI JSON summaries and the merged coverage report/archive, then removes successful raw `.xcresult` bundles, transient DerivedData, and exported intermediate coverage directories on exit. Set `CLIPBOARD_HISTORY_RETAIN_RAW_RESULTS=1` only when raw result bundles are required as release evidence. Failed runs retain their raw `.xcresult` bundles for diagnosis. Each UI test creates its isolated database under the test runner's temporary directory and removes that root plus its UserDefaults suite during teardown. This keeps reproducible evidence without accumulating rebuildable multi-gigabyte test trees in temporary storage.

The self-signed UI attempt is a separate diagnostic. It requires the stable Community identity but no Apple account or provisioning profile:

```sh
scripts/verify-community-signing.sh
```

CI uses Apple-silicon `macos-14`, `macos-15`, and `macos-26` runners. The signed UI job remains opt-in on a protected interactive arm64 runner. The current macOS 26.5 attempt did not get beyond Xcode's application-launch handshake, so this job cannot be counted as passing and does not replace manual testing of the final self-signed artifact.
