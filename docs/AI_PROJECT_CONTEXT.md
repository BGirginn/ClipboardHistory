# AI Project Context — ClipboardHistory

This file is a compact architecture map for coding agents. It is descriptive, not a replacement for reading the affected source.

## Product model

ClipboardHistory is not only a clipboard manager. It is a macOS utility hub with:

- a central Control Center,
- independently pinnable menu-bar tools,
- shared feature state/controllers,
- native system integrations,
- privacy-sensitive persistent storage.

Current first-party feature families include:

- Clipboard History
- Notes
- Input Tools
- System Monitor
- Audio Mixer

Features are static first-party modules, not arbitrary runtime plugins.

## Composition

The application composition root is centered around `AppModel` and shell-level feature registration/configuration.

Important shell concepts:

- `FeatureRegistry`
- `FeatureDescriptor`
- `UtilityFeatureID`
- `MenuBarConfiguration`
- `MenuBarConfigurationStore`
- `MenuBarController`
- Control Center models/views

The intended model is:

```text
Application / AppModel
        |
        +-- shared services
        |
        +-- feature controllers/state
        |
        +-- Control Center surfaces
        |
        +-- independent menu-bar surfaces
```

A Control Center view and an independent menu-bar surface for the same feature should observe the same underlying feature state rather than duplicate producers.

## Clipboard path

Conceptual flow:

```text
NSPasteboard
   -> monitor/capture
   -> source/content analysis
   -> sensitive/secret policy
   -> model/metadata
   -> StorageService
       -> SQLite
       -> asset files
       -> legacy decryption migration
   -> observable feature state
   -> list/detail/search/paste/presentation
```

Clipboard behavior is security-sensitive because copied data can include secrets, credentials, file paths, images, rich content, and application metadata.

## Storage and security

Storage uses SQLite plus file-backed assets and migration/recovery logic. Clipboard records use open local storage; legacy encrypted records are decrypted during the schema-v6 migration. Notes retain separate authenticated encryption backed by Keychain-managed material.

Persistent-state changes must be reasoned about as a unit:
- database rows,
- assets,
- private metadata and legacy encrypted records,
- backups,
- keys,
- collections,
- in-memory UI state.

"Deleted from the UI" is not equivalent to "deleted from persistent storage."

"Open Clipboard storage" is not equivalent to "legacy encrypted records were migrated successfully." Failed migration must preserve the old records and stop Clipboard capture.

## System Monitor

The existing architecture already implements demand-oriented centralized sampling. Do not replace it with one timer per widget.

Conceptual model:

```text
Consumers
  |-- detail view
  |-- menu bar
  `-- control center
        |
        v
SystemMetricsController
        |
  chooses active cadence
        |
        v
SystemMetricsProvider
        |
 CPU / RAM / Network / Disk / Temperature
```

Current design uses different demands/cadences for different surfaces. Extend this model rather than duplicating it.

Top-bar system metrics are intended to stay compact and primarily numeric rather than chart-heavy.

## Audio Mixer

Audio Mixer crosses multiple trust/runtime boundaries:

```text
UI/controller
   -> process discovery
   -> process audio control/pipeline
   -> CoreAudio

Browser extension
   -> native/browser bridge
   -> app
```

CoreAudio ABI/property reads, process lifetime, browser identity, native-message validation, and failure behavior need platform-specific tests.

## Menu bar

There are two distinct concepts:

1. ClipboardHistory's own `NSStatusItem` lifecycle.
2. A future external menu-bar management capability for hiding/proxying other apps' or system items.

Do not conflate them. External menu-bar management has no clean public API that simply "moves" arbitrary third-party/system items into this application's popover. Treat it as a separate capability with explicit support levels and graceful degradation.

## Non-goals for casual refactors

Do not casually:
- replace the feature registry,
- replace the shared controller model with duplicate view models,
- rewrite storage from scratch,
- replace centralized metric sampling,
- introduce a general plugin runtime,
- add heavyweight cross-platform UI frameworks.

Any such change needs an explicit architectural requirement and measured benefit.
