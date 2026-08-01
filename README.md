# ClipboardHistory

ClipboardHistory is a privacy-focused, native macOS menu bar clipboard manager written in Swift 6 with SwiftUI, AppKit, CryptoKit, SQLite, PDFKit, Quick Look, LocalAuthentication, Security, and ServiceManagement. It captures clipboard content only through `NSPasteboard`; it never watches the Desktop or any other folder.

The app has no networking, telemetry, analytics, cloud service, account system, or third-party dependency.

> **Pre-release status:** `v1.0.0-beta.1` has not been tagged or published. The current local arm64 evidence covers 202 unit/integration/benchmark tests and 7 isolated UI tests. Every production Swift file and the app aggregate are at 100% line coverage (11,850/11,850), all three build configurations are arm64-only with a macOS 14 minimum, ASan/TSan pass 201 eligible tests each, the optimized p95 benchmark passes, and all 7 critical mutations are killed. A stable self-signed Community identity is installed, and an entitlement-free `1.0.0 (10001)` artifact passes signature, designated-requirement, architecture, checksum, DMG, and SPDX checks without an Apple account or profile. Xcode UI automation cannot complete its launch handshake when the Debug app is self-signed, so clean-user manual UI/Gatekeeper evidence remains mandatory alongside the accessibility/visual matrix, eight-hour soak/Instruments, macOS 14/15/26 runs, and encrypted signing-key backup. No GitHub Release or Homebrew Cask should be advertised until [the test matrix](docs/TESTING.md) is fully green.

[Türkçe README](README_TR.md)

## Features

- Text, URL, email, file-path, and source-code classification
- Safe RTF and sanitized HTML capture with a plain-text fallback
- Single and grouped images, including screenshots copied with Control-Shift-Command-4
- Original PDF capture with page count, first-page thumbnail, restore, and Quick Look
- Single or multiple file/folder references with bookmarks, missing-file handling, Finder reveal, restore, and Quick Look
- Fielded search by text/source/type/date/collection/tag/OCR, sorting, pinned/snippet sections, keyboard navigation, context menus, details, export, and accessibility identifiers
- Separate Copy, Paste to Active App, and Paste As original/plain/RTF/sanitized-HTML actions; only direct paste requests Accessibility access
- On-device color recognition, Vision OCR, and QR decoding; extracted results follow the same encryption policy
- Encrypted titles, tags and collections; editable text, local text transformations, and reusable pinned snippets
- FIFO/LIFO temporary Paste Stack, multiple selection, drag providers, bulk deletion, age cleanup, and Command-1…9 selection
- Always-ignore transient/concealed/auto-generated pasteboard types, optional Universal Clipboard/custom UTI exclusion, and Ignore Next Copy
- Configurable System/Light/Dark appearance, shortcut activation, and a detachable keyboard-oriented panel at a selected screen edge
- Compact menu-bar controls with optional application lock plus explicit Private/Paused status, and sectioned General, Privacy, Security, Storage, and Advanced settings
- Command-Shift-V global panel shortcut, launch at login, private mode, temporary pause, and per-application exclusion rules
- Local secret detection, temporary sensitive-item retention, AES-GCM encryption, Keychain-backed keys, and an opt-in LocalAuthentication application lock
- Count, age, image-age, and storage-size retention with pinned-item preservation
- Password-protected local archives, per-entry SHA-256 manifests, validated merge import, and verified recovery import with rollback preservation
- SQLite transactions, integrity checking, crash staging cleanup, corruption preservation, JSON migration, and orphan cleanup

## Architecture

- `MenuBarController` owns the AppKit `NSStatusItem`, 380 x 500 `NSPopover`, Carbon global hotkey, and Quick Look presentation. `LSUIElement` plus the accessory activation policy keep the app out of the Dock.
- `ClipboardHistoryViewModel` is a 223-line main-actor façade. Mutation, privacy, capture, presentation, interaction, archive, and monitor responsibilities are split into isolated facets below 500 lines.
- `ClipboardMonitor` checks `NSPasteboard.general.changeCount` every 0.5 seconds. Clipboard decoding stays lightweight; hashing, normalization, conversion, and metadata work run asynchronously.
- `StorageService` is a 384-line actor façade over separate SQLite repository, asset, migration, maintenance, recovery, and encryption-rotation facets below 500 lines.
- `ThumbnailService` decodes and resizes off the main actor, never upscales, stores list thumbnails separately, regenerates missing thumbnails, cancels obsolete work, and uses a bounded `NSCache`.
- `SecretDetectionService`, `EncryptionService`, `AppLockService`, and exclusion/private-mode policy provide the local privacy boundary.
- `ExportImportService` validates archive versions, entry counts, sizes, managed paths, and record/asset manifests. `StorageRecoveryImportService` imports into isolated storage and atomically swaps only after verification.

## Requirements

- macOS 14 or later on Apple silicon (arm64 only)
- Xcode 16 or later with Swift 6 support
- The locally installed self-signed `ClipboardHistory Community Beta` identity for runnable builds; no Apple account, Development Team, or provisioning profile is required

Touch ID depends on Mac hardware and system configuration. The optional application lock also accepts the Mac login password through LocalAuthentication and never creates a separate ClipboardHistory password. Launch at login uses `SMAppService`.

## Build and test

Create the accountless signing identity once, then open `ClipboardHistory.xcodeproj` and run the scheme. The private key remains in the login Keychain and must never be committed:

```sh
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

Command-line compile without signing:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the unit and integration suite:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

All runnable configurations use the same classic login-Keychain service and stable self-signed identity. Unsigned command-line builds are compile/test inputs only; encryption operations still fail closed and never fall back to plaintext when Keychain access is denied.

Static and localization checks:

```sh
scripts/verify-static-quality.sh
```

Coverage is deliberately release-blocking and permits no source exclusion:

```sh
scripts/verify-coverage.sh /private/tmp/ClipboardHistoryTests.xcresult
```

## Run

Launch `ClipboardHistory.app`. A clipboard symbol appears only in the menu bar. Click it or press Command-Shift-V to open the panel. The shortcut uses the native Carbon hotkey API and reports registration failures returned by macOS instead of crashing; no Accessibility permission is required for registration.

Copy supported content, choose an old item to restore it, or press Space to Quick Look the keyboard-selected item. The monitor records a programmatic-restore hash and ignores the resulting pasteboard change, so restoring does not create a duplicate.

Global shortcut delivery can still be prevented by another application or managed-device policy. Current macOS versions can accept duplicate Carbon registrations without returning a conflict, so advance conflict detection is best effort. Launch at login and LocalAuthentication behavior should be verified from a normal signed interactive session.

## Local storage

```text
~/Library/Application Support/ClipboardHistory/
├── history.sqlite3
├── history.sqlite3-wal
├── history.sqlite3-shm
├── Images/
├── Thumbnails/
├── Payloads/
├── Backups/
└── .staging/
```

- Images are normalized to original PNG files; TIFF is converted to PNG. No Base64 image storage is used.
- PDFs remain unchanged in `Payloads`. Safe rich-text payloads are stored separately.
- File clipboard items retain references/bookmarks and never duplicate the referenced file automatically.
- Encrypted assets add an `.enc` physical suffix. The logical filename remains in metadata.
- App preferences remain in `UserDefaults`; storage migration markers use the SQLite `Settings` table.

## SQLite schema

`ClipboardItems` contains:

```text
id, type, textContent, imageFilename, thumbnailFilename, contentHash,
createdAt, lastUsedAt, pinnedAt, isPinned, useCount, contentSubtype,
expiresAt, isSensitive, sourceApplicationBundleID, storageVersion,
displayTitle, payloadFilename, assetFilenames, fileURLs, fileBookmarks,
imageWidth, imageHeight, pageCount, fileSize, isEncrypted,
protectedMetadata, collectionID, isSnippet, pasteboardTypes
```

`ClipboardCollections` stores identifiers and encrypted collection payloads. `Settings(key, value)` stores migration state. `SchemaMigrations(version, appliedAt)` records applied schema versions. Indexes cover creation date, last use, content hash, item type, pin state, expiry, collection, snippet, and searchable text.

Every value write uses a bound prepared statement. Multi-record changes and migrations use `BEGIN IMMEDIATE`, commit on success, and roll back on error. SQLite uses full mutex mode, WAL, a busy timeout, foreign-key enforcement, and startup `quick_check` integrity validation.

## JSON-to-SQLite migration and recovery

On first start with legacy `history.json`:

1. Storage directories and an empty schema are created.
2. The JSON file is copied to `Backups/history-before-sqlite-<uuid>.json`.
3. Backward-compatible `Codable` defaults decode old item records.
4. All records are inserted inside one transaction.
5. The migration marker is committed and the source JSON is moved to `Backups/history-migrated-<uuid>.json`.

The migration is idempotent. A simulated or real failure rolls the transaction back and preserves the source as a failed-migration backup; the new database remains usable. On database corruption, the corrupt database is preserved, recovery is attempted, and a fresh database is created only when recovery is not possible.

At startup, abandoned staged files are removed, incomplete image groups/PDF records are reconciled, missing-asset records are removed, and unreferenced managed assets/thumbnails are deleted. Asset writes stage data before atomic replacement.

## Clipboard formats

The monitor prefers file URLs, then PDF, images, and finally rich/plain text. It uses Uniform Type Identifiers rather than filename extensions.

- Plain text, URLs, email addresses, file paths, and probable source code
- RTF and HTML plus plain text; HTML scripts, event handlers, embedded objects, frames, and remote resources are removed and HTML is never executed
- PNG, TIFF, JPEG, HEIC, GIF, BMP, and multiple pasteboard image items
- PDF without rasterizing the stored original
- Single or multiple file/folder URLs with bookmarks
- Plain-text fallback when rich clipboard data cannot be safely retained

## Privacy and security

The source frontmost bundle identifier is sampled when `changeCount` changes. Allowed rules override editable exclusions. Suggested password-manager exclusions are defaults only and can be changed. Private Mode and 5/15/60-minute pauses reject new captures while keeping restore available.

Secret detection combines known prefixes and regular expressions, key-value context, password-manager source hints, content length, private-key markers, Luhn checks, and Shannon entropy. By default, detected content:

- exists only in memory;
- is excluded from persistence, indexing, backups, and disk thumbnails;
- is labelled Sensitive and expires after 60 seconds;
- is removed from UI immediately on expiry.

Detection is heuristic and can have false positives and false negatives. It is not a substitute for password-manager or organizational data-loss-prevention policy.

Stored encryption uses AES-GCM authenticated encryption with a random 256-bit master key. Every runnable configuration keeps the same master key in the macOS login Keychain, with access bound to the stable self-signed Community Beta identity. Sensitive-only encryption is the default encryption mode; all-item encryption is optional. Encrypted text and protected metadata are stored as ciphertext BLOB data, while image, thumbnail, PDF, and rich payload bytes are encrypted before disk write and decrypted only on demand. Decrypted thumbnail caches are invalidated on lock/private-mode changes.

Metadata such as item type, dates, pin state, sizes, hashes, source bundle identifier, logical filenames, and record counts remains visible in SQLite. User titles, tags, collection names, OCR, and QR results are protected. Full-database encryption is not claimed.

Application lock is off by default. Enabling or disabling it requires Touch ID or the Mac login credential through LocalAuthentication; no separate app password or verifier is stored. Once enabled, later launches begin locked. A locked app hides previews, rejects copy/restore/paste, and clears decrypted caches. With “Continue recording while locked” enabled, new items are encrypted and saved; disabling it consumes and drops new changes. Private Mode and pause always take precedence.

Logging uses `os.Logger` and records only operation type/status, anonymized identifiers, error category, timing, and migration version. Clipboard text, secret values, decrypted data, raw image/PDF bytes, and unnecessary full paths are never logged.

## Retention and deletion

Background cleanup enforces the unpinned item count, general age, image age, and total managed-storage limit. Pinned items are preserved. Database changes are transactional; associated images, image groups, thumbnails, PDFs, and rich payloads are removed and thumbnail cache entries are invalidated.

Clear History rotates the encryption master key after removing records/assets, providing cryptographic erasure for content encrypted under that key. File removal and cache clearing are best effort. APFS snapshots, SSD wear levelling, backups, and filesystem internals mean physical overwrite cannot be guaranteed.

## Export and import

Exports support metadata-only JSON, a full unencrypted archive after explicit warning, or a password-protected archive. Password archives derive a key with PBKDF2-HMAC-SHA256 (200,000 rounds) and seal the payload with AES-GCM. Temporary sensitive items are never exported; images and file references can be excluded.

Imports validate the archive version, total size, item count, asset names, and record structure; reject traversal names; and merge through duplicate detection and prepared storage writes. Imports never execute SQL from an archive and do not overwrite current history silently.

## Performance observations

The optimized Release/p95 gate and remaining live-process thresholds are recorded in [the performance report](docs/PERFORMANCE.md). The automated benchmark is release evidence; Instruments, live panel timing, CPU/RSS measurements, and the eight-hour soak remain mandatory.

## Known platform limitations and review boundary

- File bookmarks cannot make deleted files, disconnected volumes, or revoked permissions available; those rows display a missing/unavailable state.
- Pasteboard providers decide which representations are exposed. Restoring multiple independent image objects is best effort within AppKit pasteboard semantics.
- Quick Look support depends on the installed system preview generator.
- Native Carbon hotkey registration may not report that another process already owns the same key combination; actual shortcut delivery is the final authority.
- Secret detection is deliberately conservative but not perfect.
- Keychain encryption and Touch ID require a properly signed app and an interactive user session. An unsigned command-line build fails closed.
- Best-effort deletion cannot promise physical erasure on APFS/SSD media.
- The Community configuration is intentionally not Apple-notarized. It must retain quarantine and present the normal Gatekeeper warning; no installer may suppress it.
- The project does not include cloud synchronization, mobile clients, team sharing, remote servers, telemetry, AI, App Store packaging, or a currently published production distribution.

See the [beta readiness report](docs/BETA_READINESS_REPORT.md), [architecture](docs/ARCHITECTURE.md), [privacy and threat model](docs/PRIVACY_AND_THREAT_MODEL.md), [testing](docs/TESTING.md), [known limitations](docs/KNOWN_LIMITATIONS.md), [security policy](SECURITY.md), and [contributing](CONTRIBUTING.md).

Before production distribution, perform an independent security review of secret heuristics, cryptographic lifecycle, import fuzzing, login-Keychain ACL behavior, bookmark scope behavior, and privacy logging; then profile with Instruments and verify Touch ID, screen lock, launch at login, menu bar interaction, and global-shortcut conflicts on supported macOS versions.
