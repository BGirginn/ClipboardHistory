# Test and release matrix

No single layer is sufficient. A beta tag requires retained evidence from the exact release commit and exact arm64 artifact for every row below.

| Gate | Required evidence | Last recorded stabilization status (2026-08-12; historical until rerun) |
|---|---|---|
| Swift build | arm64 Debug, Release, CommunityRelease; macOS 14.2 minimum; zero compiler/analyzer/linker diagnostics | All three configurations passed the arm64 and macOS 14.2 gate, including the login helper, XPC service, and Safari extension |
| Unit/integration | Model, pasteboard, storage, legacy decryption migration, Notes encryption, lock lifecycle, search, stack, OCR/QR | 291 tests passed; 0 failed |
| Fuzz | 10,000+ deterministic hostile inputs plus malformed archive/media cases | 10,000 hostile archive/HTML/path inputs and 512 malformed PNG/JPEG/GIF/TIFF/BMP/HEIC/PDF/RTF corpus cases passed |
| Coverage | Aggregate production line coverage >=95%; every executable production Swift source has nonzero coverage; files below 80% are reported | 291 unit and 10 UI tests passed during the latest capture at 95.80% aggregate. Native CoreAudio/event-tap lifecycle and remaining UI/error paths remain documented coverage debt |
| UI automation | Status item, shortcut, panel/menu tracking, keyboard, settings, lock, paste, drag/drop, import/export | 10 ad-hoc coverage tests and 10 Community-signed UI tests passed |
| Accessibility/visual | macOS 14/15/26, light/dark, high contrast, reduced motion/transparency, 200%, Turkish/English, VoiceOver/focus, small/multiple displays | Partial render and Turkish smoke evidence only; full matrix pending |
| Performance | Optimized arm64 Release, warm-up, 10+ runs, p95 thresholds | Optimized arm64 p95 benchmark passed; the new eight-hour and Instruments evidence is pending |
| Sanitizers | ASan and TSan separately with `ENABLE_DEBUG_DYLIB=NO` and zero diagnostics | ASan 290 passed and TSan 290 passed; no sanitizer diagnostic |
| Mutation | Pasteboard identity, retention, authenticated decryption, search, archive, lock capture, open-storage migration | 7 killed, 0 survived |
| Soak/Instruments | Eight hours; idle CPU <1%; RSS <75 MB; <10% post-warm-up growth; no crash/hang; SQLite integrity; Time Profiler/Leaks/Energy/Concurrency | Not rerun for the stabilization candidate |
| Compatibility | arm64 on macOS 14, 15, and 26 | macOS 26.5 arm64 passed locally; macOS 14/15 and exact release-commit matrix evidence pending |
| Distribution | Stable self-signed certificate and encrypted backup, quarantined clean-user install, checksums, SPDX SBOM, Cask audit/install/upgrade/uninstall | Signing identity and history/working-tree secret scans passed. The Community beta may be published with incomplete physical acceptance explicitly disclosed; it must not be represented as notarized or production-stable |

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

The script uses unsigned unit tests and an ad-hoc-signed UI build with the empty production entitlement file. Unit, UI, sanitizer, mutation and performance runs use the `ClipboardHistoryTests` scheme and the separate `ClipboardHistoryTestHost` application. It compiles the same application sources with `CLIPBOARD_HISTORY_TEST_HOST`, an isolated bundle identifier, and no embedded login or browser helpers. UI composition injects temporary storage, a named pasteboard, a dedicated UserDefaults suite, ephemeral keys, and inert input, authentication, paste, login, metrics and audio adapters. The production application does not compile test routing, even in Debug. Optimized host results validate shared code; they do not validate native adapters or the packaged production application.

The suite retains compact unit/UI JSON summaries and the merged coverage report/archive, then removes successful raw `.xcresult` bundles, transient DerivedData, and exported intermediate coverage directories on exit. Set `CLIPBOARD_HISTORY_RETAIN_RAW_RESULTS=1` only when raw result bundles are required as release evidence. Failed runs retain their raw `.xcresult` bundles for diagnosis. Each UI test creates its isolated database under the test runner's temporary directory and removes that root plus its UserDefaults suite during teardown. This keeps reproducible evidence without accumulating rebuildable multi-gigabyte test trees in temporary storage.

Coverage evidence directories named `clipboardhistory-coverage-*` or
`ClipboardHistoryCoverage*` under `/private/tmp` participate in the same 2 GiB
and 24-hour cleanup policy. Copy release evidence out of temporary storage when
it must be retained longer.

The self-signed UI attempt is a separate diagnostic. It requires the stable Community identity but no Apple account or provisioning profile:

```sh
scripts/verify-community-signing.sh
```

CI uses Apple-silicon `macos-14`, `macos-15`, and `macos-26` runners with Xcode 16.2, 26.3, and 26.5 respectively. Pinning installed toolchains prevents runner-default changes from silently changing the OS matrix. Hosted builds also disable Swift batch compilation because these toolchains can crash the Swift frontend while compiling this target's SwiftUI files in multi-primary-file batches. Release optimization settings are unchanged. The signed UI job remains opt-in on a protected interactive arm64 runner. The current macOS 26.5 Community-signed UI run passed all ten automated tests, but it does not replace physical input/audio/browser checks or the external OS matrix.

Browser messaging regression tests use Node's built-in runner and mocked extension APIs:

```sh
node --test Tests/Browser/BrowserAudioMessagingTests.cjs
```

`verify-performance.sh` exports the optimized benchmark's JSON attachment before removing transient build data. The 5,000-item first-layout budget is 50 ms; the 120 ms status-item-to-visible-frame budget is a separate native measurement. Do not substitute the layout benchmark for frame-presentation or eight-hour soak evidence.
