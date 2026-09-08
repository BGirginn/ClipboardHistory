# Native experience implementation

This document tracks the current working-tree implementation; it is not release evidence.

## Architecture and behavior

- Control Center remains the primary menu-bar entry. Shared controllers serve a compact 340–420 pt panel and a reusable wider window. Open in Window retains routing, Clipboard selection/search and the Notes draft.
- Clipboard search is explicitly opened with the magnifier, focuses on appearance, and clears its query when closed. It has no search keyboard shortcut.
- Notes distinguishes pending edits from a completed save and retains list position. Navigation checks request and route generations after asynchronous saves.
- System Monitor initially presents numbers; charts and sensor detail are created only when expanded. Its shared producer uses 1/2/5-second detail/menu-bar/Control Center demand, doubled in Low Power Mode, and stops without consumers.
- Native popover animation remains enabled. SwiftUI transitions share a 140 ms policy and respect Reduce Motion. Reduce Transparency uses an opaque background.
- Keyboard Cleaning's card opens the module; a separate button starts or stops it. Audio rows retain stable slider layout and ignore external volume updates while being dragged.

## Reliability boundaries

Clear retains quarantine if rollback cannot restore assets and blocks further writes until recovery. Quota accounting excludes items already selected by retention. Capture generation invalidates work across Clear, privacy and shutdown; Clear/shutdown drain operations that have begun materializing data before proceeding. Failed persistent deletion retains UI and pasteboard identity. Import loads Notes before materializing assets and reports cleanup failure. Browser commands are source-scoped; resetting audio also removes preferences for closed applications.

Chromium no longer responds to empty/unchanged native commands with another state message. Chromium and Safari heartbeat timers stop when no controlled tabs remain. Safari coalesces concurrent native requests.

## Validation boundaries

The separate test host has its own bundle identifier and isolated composition root. Native adapters are not validated by its stubs. Production builds are checked separately. Unit rendering uses installed hosting views rather than reading detached SwiftUI State/Environment values; interactive editing belongs in UI tests.

Required acceptance evidence still includes native event-to-frame timing, missed frames, idle CPU/RSS, an eight-hour soak, physical CoreAudio/Accessibility/browser behavior, VoiceOver and macOS version coverage. These must not be marked complete from unit tests or a short benchmark.

## Verification record — 2026-09-07

- Development suite: 324 tests passed, zero runtime warnings. Includes seven reliability regressions, closed-application audio reset, shared low-power sampling, coalesced Notes reads and window transfer state preservation. The transfer test creates only one window across 100 requests; it does not measure native animation frames.
- Chromium/Safari mocked messaging: 2 tests passed. Empty/unchanged acknowledgements do not cause a Chromium response loop; Safari requests coalesce; idle heartbeat timers stop.
- Optimized arm64 test host, 5,000 items, 20 repetitions: p95 write 32.754 ms, read 17.613 ms, model load 74.267 ms, filter 9.309 ms, first layout 17.360 ms. All five budgets passed.
- Production Debug/Release/CommunityRelease arm64 build gate passed with zero compiler/linker diagnostics; embedded helpers and macOS 14.2 deployment target checked.
- Static quality, localization extraction/catalog compilation and diff whitespace checks passed.
- Targeted UI search/window-transfer regression passed after moving the focus request to a task yield. It verifies magnifier focus, query preservation through window transfer, panel closure and clearing the query when closing search. An earlier full UI attempt timed out during automation initialization. The subsequent completed suite passed 14 of 16 tests: the detail editing test exposed missing bulk-synthesized lowercase i input, and customization attempted to click a control outside the viewport. These failures are tracked in the September 8 follow-up below.

## UI follow-up — 2026-09-08

The detail editor regression now sends individual key events on the Turkish-PC keyboard layout while retaining the exact expected text, space and arrow assertions. The targeted run passed those assertions and revealed that the `clipboard.detail` container identifier overrode the Back, Copy and Open in Window button identifiers in the accessibility tree. Removing the unused container identifier restores the individual controls. The test also reopens the saved item and checks its title.

The full follow-up UI run passed 15 of 16 tests with zero runtime warnings, including detail editing and reopening. The remaining customization failure revealed that `MenuBarFeatureConfigurationCard` did not observe configuration changes and displayed stale picker values. It now observes the shared model directly. The regression checks the selected values and requires controls to lie fully inside the form viewport: macOS reported a switch behind the toolbar as hittable. Icon removal is checked with an absence expectation. Independent Clipboard status-item checks remain. The corrected customization regression passed in a separate targeted run, with zero runtime warnings. This is 15 passing tests from the full run plus the subsequently repaired targeted test, not a claim that a final full 16-test run was repeated.

Final-source development suite: 324 passed, zero failures, zero runtime warnings. Browser messaging tests: 2 passed. Static quality, localization and diff whitespace checks passed. Production Debug/Release/CommunityRelease builds passed without compiler/linker warnings; the arm64 gate verified embedded components, the LaunchAgent and the macOS 14.2 deployment minimum. The optimized benchmark was not repeated for these UI-only changes; its September 7 measurements remain separately dated above.

### Remaining acceptance work

The plan is not fully accepted yet. Comprehensive editor/IME and keyboard-layout coverage, injected error/retry UI dialogs, full TR/EN coverage across all modules, VoiceOver, native first-visible-frame timing, missed-frame rate, timer/observer/task counts during real 100 open/close cycles, idle CPU/RSS, and the eight-hour soak still need retained evidence. The existing English interaction tests and Turkish core-panel localization test passed; they do not cover every module, layout or accessibility preference. CoreAudio, browser installation/control, Accessibility and the macOS version matrix require real-adapter runs. No installation, commit, push or publication was performed.
