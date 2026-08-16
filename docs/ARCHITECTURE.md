# Architecture

ClipboardHistory is a local-first modular menu-bar application. `AppModel` is the composition root for shared services and independently owns Clipboard, Notes, Keyboard Cleaning, Scroll Reverse, System Monitor, Audio Mixer, Control Center, and Settings models. `FeatureRegistry` is the compile-time catalog; `MenuBarConfigurationStore` persists versioned placement and validated click actions in `UserDefaults`. `AppRouter` owns the current `AppFeature`, selected Settings section, and Settings return point. `ClipboardHistoryAppDelegate` keeps the process in accessory mode while the main Control Center status item is enabled; hiding that item switches to regular activation policy so Finder and Dock reopen events can present `AppShellView` through `ApplicationWindowController` in a standard window. `MenuBarController` dynamically owns the enabled module/metric status items, one shared popover, detachable panel, Quick Look, and outside-click behavior, and falls back to the application window when a shortcut has no status-item anchor. `PanelCloseCoordinator` defers panel closure during context-menu and modal confirmation tracking so a command can complete without leaving the UI stuck.

`ClipboardHistoryViewModel` is now Clipboard-only. Its mutation, privacy/settings operations, capture, presentation, interaction/write-coordination, archive, and monitor-delegate facets live in separate files and retain the façade's main-actor isolation. `NoteController` owns note search, the mutually exclusive `NoteScreen.list`/`.editor` state, validation, and revision-aware serialized debounced/forced saves. `InputToolsController` owns the shared event-tap coordinator plus `KeyboardCleaningController` and `ScrollReversalController`; workspace lifecycle handling no longer leaks into the Clipboard model. `SettingsFeatureModel` composes app-wide Settings, while each feature-specific Settings view observes its actual controller. Settings navigation uses two horizontal shelves: the upper shelf selects the owning app or module and the lower shelf exposes only that owner's subsections. Sensitive Clipboard previews and restore operations authenticate through the injected `SystemAuthenticating` boundary.

`InputEventTapCoordinator` owns one dynamic session event tap shared by Keyboard Cleaning and Scroll Reverse. Keyboard Cleaning discards keyboard/media events for at most 60 seconds while leaving mouse/scroll available; Scroll Reverse mutates enabled line-based or precise axes in place. Neither path records or logs input content. Direct paste and Input Tools ask macOS for Accessibility access. Clock, timer, authentication, Accessibility trust/event creation, launch-at-login, pasteboard, drag provider, Quick Look presentation, status-item/panel creation, content analysis, storage-operation failure, filesystem migration, and master-key boundaries are injectable.

`SystemMetricsController` activates its provider only while a detail view, Control Center card, or menu-bar metric consumes samples. Mach CPU ticks, VM statistics, physical network counters, IOKit storage counters, AppleSMC/Apple Silicon HID die temperatures, and Foundation thermal state are combined into an in-memory snapshot and a time-bounded 15-minute ring buffer. `AudioMixerController` discovers Core Audio process objects and creates a private process-tap pipeline only below 100% gain. Browser tabs enter through bounded native messages from the bundled Chromium resources or Safari Web Extension; browser state remains memory-only.

`ClipboardMonitor` observes `changeCount`, records pasteboard identity, ignores known transient/concealed/auto-generated types, and optionally ignores Universal Clipboard or custom UTIs. Transient, unsupported, excluded, paused, and application-generated changes never reach Clipboard insertion. Deletion clears the system pasteboard only while the stored identity still matches, preserving clipboard data copied after the history item was recorded.

`StorageService` is an actor façade over SQLite WAL and staged assets. Actor-isolated repository, asset-store, schema/legacy-migration, maintenance, recovery, and note-encryption facets live in separate files. Database mutations remain transactional; asset writes retain staging before finalization, and failure paths roll back. Schema v2 added protected metadata and collection membership; schema v3 added collections; schema v4 added the independent encrypted `Notes` table; schema v5 consolidated Clipboard private metadata; schema v6 migrates Clipboard metadata and collections to open local storage and removes the Clipboard startup Keychain dependency. Clear History moves Clipboard assets and backups into a same-volume operation quarantine, commits item and collection deletion, and finishes or restores interrupted operations at startup. Note titles and bodies remain protected by their separate Keychain account.

Browser audio control crosses process boundaries through the embedded `ClipboardHistoryBrowserAudioBridge.xpc` service. The main app exports the controller callback; the Chromium native host and Safari extension exchange only versioned bounded data messages. The service validates the live caller signature, allowlisted bundle identifier, UID, and signing-certificate equality before accepting a connection.

`ExportImportService` authenticates v3 password archives, validates clipboard and note counts, sizes, managed paths, and SHA-256 manifests, materializes accepted merge records before one item/collection/note transaction, and removes rejected assets. Metadata-only archives exclude content-derived private metadata, collections, notes, and assets; full encrypted and unencrypted archives include them. v1/v2 archives remain importable with an empty note set. `StorageRecoveryImportService` closes SQLite before filesystem moves, preserves the existing destination as a rollback backup, and only swaps the verified staging directory into place.

Debug, Release, and `CommunityRelease` use an empty entitlement file and the stable self-signed `ClipboardHistory Community Beta` identity. The classic login Keychain protects Notes and supports one-time migration of legacy encrypted Clipboard records; current Clipboard storage is open and has no startup Keychain dependency. The embedded `ClipboardHistoryLoginItem` helper launches the main app with `--background-launch` and exits, keeping login launch silent; the launch-at-login service migrates the former `SMAppService.mainApp` registration to this helper. No Apple account or provisioning profile is required. The certificate's private key must never enter Git. The community artifact is not Apple-notarized and must not bypass Gatekeeper or quarantine.

The static quality gate enforces a maximum of 500 lines and one top-level struct, class, enum, actor, or protocol per production Swift source file so these boundaries cannot silently regress.

## Project layout

The Xcode targets use file-system-synchronized groups, so the directory tree is the source of truth. The layout stays deliberately shallow: a subdirectory is retained only when it represents a real platform, security, persistence, or UI boundary.

```text
.
├── .github/                  # CI workflows and GitHub community files
├── ClipboardHistory/         # Application source and bundled resources
│   ├── Application/
│   │   └── Shell/            # AppModel, AppRouter, and root shell
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
