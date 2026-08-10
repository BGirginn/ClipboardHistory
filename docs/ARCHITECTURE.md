# Architecture

ClipboardHistory is a local-first modular menu-bar application. `AppModel` is the composition root for shared services and independently owns Clipboard, Notes, Keyboard Cleaning, Scroll Reverse, System Monitor, Audio Mixer, Control Center, and Settings models. `FeatureRegistry` is the compile-time catalog; `MenuBarConfigurationStore` persists versioned placement and validated click actions in `UserDefaults`. `AppRouter` owns the current `AppFeature`, Settings return point, and lock location. A normal Finder launch or reopen presents Control Center while the global shortcut routes directly to Clipboard. `MenuBarController` dynamically owns the Control Center and enabled module/metric status items, one shared popover, detachable-panel, Quick Look, and outside-click behavior. `PanelCloseCoordinator` defers panel closure during context-menu tracking so a menu command can complete without leaving the UI stuck.

`ClipboardHistoryViewModel` is now Clipboard-only. Its mutation, privacy/settings operations, capture, presentation, interaction/write-coordination, archive, and monitor-delegate facets live in separate files and retain the façade's main-actor isolation. `NoteController` owns note search, the mutually exclusive `NoteScreen.list`/`.editor` state, validation, and revision-aware serialized debounced/forced saves. `InputToolsController` owns the shared event-tap coordinator plus `KeyboardCleaningController` and `ScrollReversalController`; lock and workspace lifecycle handling no longer leaks into the Clipboard model. `SettingsFeatureModel` is the Settings-facing façade over shared preferences and authorized Clipboard maintenance operations.

`InputEventTapCoordinator` owns one dynamic session event tap shared by Keyboard Cleaning and Scroll Reverse. Keyboard Cleaning discards keyboard/media events for at most 60 seconds while leaving mouse/scroll available; Scroll Reverse mutates enabled line-based or precise axes in place. Neither path records or logs input content. Direct paste and Input Tools ask macOS for Accessibility access. Clock, timer, authentication, Accessibility trust/event creation, launch-at-login, pasteboard, drag provider, Quick Look presentation, status-item/panel creation, content analysis, storage-operation failure, filesystem migration, and master-key boundaries are injectable.

`SystemMetricsController` activates its provider only while a detail view, Control Center card, or menu-bar metric consumes samples. Mach CPU ticks, VM statistics, physical network counters, IOKit storage counters, AppleSMC/Apple Silicon HID die temperatures, and Foundation thermal state are combined into an in-memory snapshot and a time-bounded 15-minute ring buffer. `AudioMixerController` discovers Core Audio process objects and creates a private process-tap pipeline only below 100% gain. Browser tabs enter through bounded native messages from the bundled Chromium resources or Safari Web Extension; browser state remains memory-only.

`ClipboardMonitor` observes `changeCount`, records pasteboard identity, ignores known transient/concealed/auto-generated types, and optionally ignores Universal Clipboard or custom UTIs. Transient, unsupported, excluded, paused, locked, and application-generated changes never reach Clipboard insertion. Deletion clears the system pasteboard only while the stored identity still matches, preserving clipboard data copied after the history item was recorded.

`StorageService` is an actor façade over SQLite WAL and staged assets. Actor-isolated repository, asset-store, schema/legacy-migration, maintenance, recovery, and encryption-rotation facets live in separate files. Database mutations remain transactional; asset writes retain staging before finalization, and failure paths roll back without plaintext fallback. Schema v2 added encrypted protected metadata and collection membership; schema v3 added encrypted collections; schema v4 added the independent `Notes` table. Note titles and bodies are always AES-GCM BLOBs protected by a separate Keychain account, so clipboard-history cryptographic erasure cannot invalidate notes. Visible names, tags, OCR/QR results, and collection names are encrypted with AES-GCM. Public metadata remains queryable as documented in the threat model.

`ExportImportService` authenticates v3 password archives, validates clipboard and note counts, sizes, managed paths, and SHA-256 manifests, materializes into isolated staging storage, and verifies the result. Metadata-only archives exclude notes; full encrypted and unencrypted archives include them. v1/v2 archives remain importable with an empty note set. `StorageRecoveryImportService` closes SQLite before filesystem moves, preserves the existing destination as a rollback backup, and only swaps the verified staging directory into place.

One signing/key mode exists. Debug, Release, and `CommunityRelease` use the classic login Keychain, an empty entitlement file, and the stable self-signed `ClipboardHistory Community Beta` identity. The embedded `ClipboardHistoryLoginItem` helper launches the main app with `--background-launch` and exits, keeping login launch silent; the launch-at-login service migrates the former `SMAppService.mainApp` registration to this helper. No Apple account or provisioning profile is required. The certificate's private key must never enter Git. The community artifact is not Apple-notarized and must not bypass Gatekeeper or quarantine.

The static quality gate enforces a maximum of 500 lines and one top-level struct, class, enum, actor, or protocol per production Swift source file so these boundaries cannot silently regress.

## Project layout

The Xcode targets use file-system-synchronized groups, so the directory tree is the source of truth. The layout stays deliberately shallow: a subdirectory is retained only when it represents a real platform, security, persistence, or UI boundary.

```text
.
├── .github/                  # CI workflows and GitHub community files
├── ClipboardHistory/         # Application source and bundled resources
│   ├── Application/
│   │   └── Shell/            # AppModel, AppRouter, root shell, and lock routing
│   ├── Features/
│   │   ├── Clipboard/        # Clipboard model facets, panel, rows, detail, and menus
│   │   ├── ControlCenter/    # Module dashboard and menu-bar customization
│   │   ├── InputTools/       # Input lifecycle model, keyboard cleaning, and scroll UI
│   │   ├── Notes/            # Note controller, list, and exclusive editor screen
│   │   ├── SystemMonitor/     # CPU, RAM, temperature, network, and disk metrics
│   │   ├── AudioMixer/        # Process audio and authorized browser-tab controls
│   │   └── Settings/         # Settings façade, preferences, and section views
│   ├── Models/               # Shared domain values and operation results
│   ├── Services/
│   │   ├── Clipboard/        # Capture, processing, metadata, and pasteboard writes
│   │   ├── Pasting/          # Direct paste, Accessibility, and drag providers
│   │   ├── Presentation/     # Menu bar, panel lifecycle, Quick Look, thumbnails
│   │   ├── Security/         # Authentication, Keychain, and cryptography
│   │   ├── Storage/          # SQLite, assets, migrations, archive, and maintenance
│   │   └── System/           # Shortcuts, launch at login, timers, and logging
│   ├── Shared/               # Cross-feature design tokens and shell components
│   └── Utilities/            # Small stateless helpers
├── ClipboardHistoryLoginItem/ # Silent signed login-item helper
├── ClipboardHistorySafariExtension/ # Safari Web Extension and native message handler
├── ClipboardHistory.xcodeproj/ # Xcode targets, settings, and shared scheme
├── Tests/
│   ├── Unit/                 # Unit/integration tests and named test doubles
│   └── UI/                   # End-to-end UI automation
├── docs/                     # Architecture, testing, release, and policy details
├── scripts/                  # Quality, coverage, build, and release automation
├── .gitignore
├── LICENSE
└── README.md                 # Primary project entry point
```

Features are static first-party modules rather than runtime plugins. Adding one requires an `AppFeature` case, an independently owned feature model/view, and only the shared services it consumes. Models and each test target stay flat where filenames already identify their subject. Service folders remain separate because they enforce platform, security, and persistence boundaries. A protocol and its concrete system adapter use separate files, while same-type extensions may remain split by responsibility.
