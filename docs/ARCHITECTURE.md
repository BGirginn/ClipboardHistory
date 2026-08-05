# Architecture

ClipboardHistory is a local-only menu-bar application. `MenuBarController` owns status-item, popover, detachable-panel, Quick Look, and outside-click behavior. `PanelCloseCoordinator` defers panel closure during context-menu tracking so a menu command can complete without leaving the UI stuck.

`ClipboardHistoryViewModel` is a main-actor façade. Its mutation, privacy/settings, capture, presentation, interaction/write-coordination, archive, and monitor-delegate facets live in separate files and retain the façade's main-actor isolation. Pasteboard writing and direct paste are separate services; only direct paste asks macOS for Accessibility access. Clock, timer, authentication, Accessibility trust/event creation, launch-at-login, pasteboard, drag provider, Quick Look presentation, status-item/panel creation, content analysis, storage-operation failure, filesystem migration, and master-key boundaries are injectable.

`ClipboardMonitor` observes `changeCount`, records pasteboard identity, ignores known transient/concealed/auto-generated types, and optionally ignores Universal Clipboard or custom UTIs. Deletion clears the system pasteboard only while the stored identity still matches, preserving clipboard data copied after the history item was recorded.

`StorageService` is an actor façade over SQLite WAL and staged assets. Actor-isolated repository, asset-store, schema/legacy-migration, maintenance, recovery, and encryption-rotation facets live in separate files. Database mutations remain transactional; asset writes retain staging before finalization, and failure paths roll back without plaintext fallback. Schema v2 added encrypted protected metadata and collection membership; schema v3 added encrypted collections. Visible names, tags, OCR/QR results, and collection names are encrypted with AES-GCM. Public metadata remains queryable as documented in the threat model.

`ExportImportService` authenticates password archives, validates counts, sizes, managed paths, and SHA-256 manifests, materializes into isolated staging storage, and verifies the result. `StorageRecoveryImportService` closes SQLite before filesystem moves, preserves the existing destination as a rollback backup, and only swaps the verified staging directory into place.

One signing/key mode exists. Debug, Release, and `CommunityRelease` use the classic login Keychain, an empty entitlement file, and the stable self-signed `ClipboardHistory Community Beta` identity. No Apple account or provisioning profile is required. The certificate's private key must never enter Git. The community artifact is not Apple-notarized and must not bypass Gatekeeper or quarantine.

The static quality gate enforces a maximum of 500 lines and one top-level struct, class, enum, actor, or protocol per production Swift source file so these boundaries cannot silently regress.

## Project layout

The Xcode targets use file-system-synchronized groups, so the directory tree is the source of truth. The layout stays deliberately shallow: a subdirectory is retained only when it represents a real platform, security, persistence, or UI boundary.

```text
.
├── .github/                  # CI workflows and GitHub community files
├── ClipboardHistory/         # Application source and bundled resources
│   ├── Application/          # Process entry point and app delegate
│   ├── Models/               # Flat domain values, settings, and operation results
│   ├── Services/
│   │   ├── Clipboard/        # Capture, processing, metadata, and pasteboard writes
│   │   ├── Pasting/          # Direct paste, Accessibility, and drag providers
│   │   ├── Presentation/     # Menu bar, panel lifecycle, Quick Look, thumbnails
│   │   ├── Security/         # Authentication, Keychain, and cryptography
│   │   ├── Storage/          # SQLite, assets, migrations, archive, and maintenance
│   │   └── System/           # Shortcuts, launch at login, timers, and logging
│   ├── Utilities/            # Small stateless helpers
│   ├── ViewModels/           # View-model façade, facets, adapters, and settings
│   └── Views/
│       ├── Items/            # Rows, menus, detail screens, and previews
│       ├── Panel/            # Main panel composition and navigation
│       └── Settings/         # Settings sections and supporting controls
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

Models and each test target stay flat inside their target directories because filenames already identify their subject and they do not form separate modules. Service folders remain separate because they enforce meaningful boundaries such as Accessibility-only direct paste, Keychain/cryptography, persistence, and AppKit presentation. View folders remain separate because they map to distinct UI surfaces with multiple components. A protocol and its concrete system adapter use separate files, while same-type extensions may remain split by responsibility.
