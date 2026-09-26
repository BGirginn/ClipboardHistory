# Changelog

All notable changes are documented here. The project follows semantic versioning from the first public beta.

## Unreleased

## 1.0.0-beta.7 - 2026-09-26

- Fixed the Settings window restoring an obsolete undersized frame or collapsing to its minimum size when SwiftUI content was replaced.
- Kept module menu-bar placement editable while a module is in the Drawer, allowing Clipboard to move directly to an always-visible menu-bar item.
- Scoped Audio Mixer gain changes to the current application process lifetime so a relaunched application starts at its native volume instead of inheriting a stale zero gain.

## 1.0.0-beta.6 - 2026-09-11

- Rebranded the user-facing application as CoreDeck while keeping Clipboard History as the clipboard module name.
- Changed the main product bundle and executable to `CoreDeck.app` and `CoreDeck`, retaining the existing Xcode project, scheme, Swift module, bundle identifiers, service identities, storage paths, defaults, Keychain service, and Community signing identity for upgrade compatibility.
- Updated English and Turkish application, permission, accessibility, Control Center, menu, Safari, and Chromium extension branding.
- Updated Community artifact names, packaging checks, and documentation for `v1.0.0-beta.6` build `10006`; the transition Homebrew command remains `brew install --cask clipboardhistory`.
- Changed new archive suggestions to `CoreDeck.clipboardarchive` and `CoreDeck-Encrypted.clipboardarchive` without changing the archive format or legacy import support.

## 1.0.0-beta.5 - 2026-09-03

- Made popover, detachable-panel, and application-window sampling visibility-aware with source-owned demand records, so one surface cannot disable another and hidden UI surfaces do not keep polling.
- Moved CoreAudio application discovery off the main actor, limited the mixer to active processes resolved to real application bundles, added application icons, and coalesced slider persistence until editing ends.
- Rebuilt menu-bar customization around Minimal, Balanced, and Custom presets, a native grouped Form, a live topbar preview, conditional `When Active` policies, drag-ordered metrics, and compact/standard density controls.
- Replaced the fixed-width SwiftUI metric title with a native AppKit segment strip using per-metric symbols, monospaced values, stable widths, complete tooltips, and incremental updates that preserve status-item identity without `+N` text.
- Removed Keyboard Cleaning's 60-second deadline; its Control Center card and standalone menu-bar item now toggle the mode until the user stops it, while lifecycle and event-tap failures still release the keyboard.
- Corrected memory accounting, moved network byte counters to 64-bit interface data, keyed physical disks by registry identity, and made the System Monitor grid switch from one column at 340 pt to two columns when space allows.
- Reworked System Monitor into a compact shared-snapshot dashboard and clarified CPU as a system-wide 0–100% metric with User/System breakdowns in the menu-bar tooltip.
- Replaced the two unlabeled Settings icon shelves with one grouped, labeled settings index; opening generic Settings no longer preselects a pane the user did not choose, and menu-bar configuration cards now use one consistent width with compact metric rows.
- Fixed temperature reporting to average verified CPU sensors, distinguish CPU and SoC readings, recognize additional Apple Silicon HID and M3/M4 SMC sensors, and show tenths in the menu bar.
- Limited Audio Mixer application rows to processes currently producing audio and kept its menu-bar icon stable so an open popover does not shift when mute state changes.
- Fixed the Clipboard panel's Clear All History confirmation so the popover remains active until the user confirms or cancels.
- Kept Clipboard capture alive through AppKit event-tracking modes, pasteboard counter resets, and cancelled quit attempts instead of leaving recording silently stopped.
- Reset pre-v4 top-bar placements once and require fresh opt-in before showing standalone modules or live system metrics; pinning System Monitor now uses one canonical CPU, RAM, and temperature metric item instead of a duplicate icon.
- Migrated visible CPU, RAM, and temperature metrics to independently movable native status items; CPU/RAM use compact stacked labels and temperature is value-only.
- Replaced the unreachable mixed XPC browser bridge with an on-demand LaunchAgent Mach service shared by the app, Chromium native host, and Safari extension.
- Added a separately downloadable, validated Chromium extension ZIP to Community release artifacts.
- Kept asynchronous application termination replies explicit and single-shot across successful and cancelled shutdowns.

## 1.0.0-beta.4 - 2026-08-16

- Reorganized Settings into two compact icon shelves separating application areas from feature-specific options.
- Moved Private Mode, retention cleanup, and Clear History closer to Clipboard content and removed the obsolete Application Lock feature.
- Added a normal Dock-accessible, resizable application window when the main Control Center menu-bar icon is hidden.
- Fixed popover anchoring so actions open beneath the menu-bar item that initiated them.
- Made menu-bar metrics configurable and visually stable with byte-based rates, numeric zeroes, monospaced digits, and predictable widths.
- Removed the per-core CPU list and its unnecessary sampling work.
- Resolved Audio Mixer entries to application names such as Brave Browser and Spotify instead of helper/PID identities.
- Shared Accessibility authorization across Direct Paste and Input Tools to avoid duplicate macOS prompts within one application session.
- Restored GitHub runner compatibility when `ripgrep` is absent from the base image.

## 1.0.0-beta.3 - 2026-08-12

- Converted the application into a modular Control Center with independently pinnable Clipboard, Notes, Input Tools, System Monitor, and experimental Audio Mixer features.
- Added encrypted Notes, schema-v6 open Clipboard storage with legacy encrypted-record migration, transactional history cleanup, stricter sensitive-content authorization, capture limits, and hardened import/export recovery.
- Added demand-driven CPU, memory, network, disk, and validated temperature monitoring with configurable menu-bar metric formats.
- Added experimental per-application and browser-tab audio controls with fail-open CoreAudio handling and a signed local browser bridge boundary.
- Expanded shutdown durability, menu-bar configuration, localization, static quality, sanitizer, mutation, rendering, and regression coverage.

## 1.0.0-beta.2 - 2026-08-02

- Removed the panel search bar and its Command-F focus path.
- Added a right-click menu with an explicit Quit action to the menu-bar icon.
- Preloaded and laid out popover content before its animation to eliminate frame-by-frame panel stutter.

## 1.0.0-beta.1 - 2026-08-01

- Added fail-closed encryption-key and storage error handling.
- Added protected metadata, encrypted collections, snippets, tags, editable text and titles.
- Added original/plain/RTF/sanitized-HTML Paste As and Accessibility-gated direct paste.
- Added local color recognition, Vision OCR, and QR decoding.
- Added FIFO/LIFO Paste Stack, multiple selection, drag providers, bulk and age cleanup, and Command-1…9 selection.
- Added fielded search, configurable pasteboard-type exclusions, ignore-next-copy, configurable global shortcut modes, and detachable edge panels.
- Added atomic password-archive Community migration with rollback preservation and SHA-256 manifests.
- Added English/Turkish String Catalog, isolated UI-test target, deterministic fuzzing, static/localization/coverage gates, and release documentation.
- Added optional Touch ID or Mac-login application lock with encrypted capture controls.
- Added persistent System/Light/Dark appearance and a black macOS application icon.
- Fixed panel restoration, first-click context menus, and Private Mode controls.
- Restricted the Community release to arm64 with a macOS 14 minimum.
