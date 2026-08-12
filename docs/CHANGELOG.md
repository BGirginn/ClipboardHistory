# Changelog

All notable changes are documented here. The project follows semantic versioning from the first public beta.

## Unreleased

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
