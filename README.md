# ClipboardHistory

ClipboardHistory is a private, native macOS menu bar clipboard manager written in Swift 6 with SwiftUI, AppKit, CryptoKit, SQLite, PDFKit, Quick Look, LocalAuthentication, Security, and ServiceManagement. It captures clipboard content only through `NSPasteboard`; it never watches the Desktop or any other folder.

The app has no networking, telemetry, analytics, cloud service, account system, or third-party dependency.

## Features

- Text, URL, email, file-path, and source-code classification
- Safe RTF and sanitized HTML capture with a plain-text fallback
- Single and grouped images, including screenshots copied with Control-Shift-Command-4
- Original PDF capture with page count, first-page thumbnail, restore, and Quick Look
- Single or multiple file/folder references with bookmarks, missing-file handling, Finder reveal, restore, and Quick Look
- Search, type filters, sorting, pinned sections, keyboard navigation, context menus, details, export, and accessibility identifiers
- Compact menu-bar controls with explicit Locked/Private/Paused status, plus sectioned General, Privacy, Security, Storage, and Advanced settings
- Command-Shift-V global panel shortcut, launch at login, private mode, temporary pause, and per-application exclusion rules
- Local secret detection, temporary sensitive-item retention, AES-GCM encryption, Keychain-backed keys, automatic lock, and LocalAuthentication unlock
- Count, age, image-age, and storage-size retention with pinned-item preservation
- Password-protected local archives and validated merge import
- SQLite transactions, integrity checking, crash staging cleanup, corruption preservation, JSON migration, and orphan cleanup

## Architecture

- `MenuBarController` owns the AppKit `NSStatusItem`, 380 x 500 `NSPopover`, Carbon global hotkey, and Quick Look presentation. `LSUIElement` plus the accessory activation policy keep the app out of the Dock.
- `ClipboardHistoryViewModel` is the main-actor MVVM coordinator for presentation, privacy policy, duplicate suppression, restore feedback, expiration, locking, and cleanup.
- `ClipboardMonitor` checks `NSPasteboard.general.changeCount` every 0.5 seconds. Clipboard decoding stays lightweight; hashing, normalization, conversion, and metadata work run asynchronously.
- `StorageService` is an actor around native SQLite prepared statements, WAL journaling, transactions, staged asset writes, migrations, and retention.
- `ThumbnailService` decodes and resizes off the main actor, never upscales, stores list thumbnails separately, regenerates missing thumbnails, cancels obsolete work, and uses a bounded `NSCache`.
- `SecretDetectionService`, `EncryptionService`, `AppLockService`, and exclusion/private-mode policy provide the local privacy boundary.
- `ExportImportService` validates archive versions, entry counts, sizes, and filenames before merging data through the normal storage API.

## Requirements

- macOS 13 or later
- Xcode 16 or later with Swift 6 support
- A selected Apple Development team for a runnable build that uses Data Protection Keychain

Touch ID depends on Mac hardware and system configuration. Launch at login uses `SMAppService` on macOS 13+.

## Build and test

Open `ClipboardHistory.xcodeproj`, select the `ClipboardHistory` target, choose your Development Team under Signing & Capabilities, and run the scheme.

Command-line compile without signing:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the unit and integration suite:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Unsigned builds intentionally cannot access the Data Protection Keychain. Encryption operations fail closed and do not write plaintext, but encryption must be exercised with a properly signed runnable build.

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
imageWidth, imageHeight, pageCount, fileSize, isEncrypted
```

`Settings(key, value)` stores migration state. `SchemaMigrations(version, appliedAt)` records applied schema versions. Indexes cover creation date, last use, content hash, item type, pin state, expiry, and searchable text.

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

Stored encryption uses AES-GCM authenticated encryption with a random 256-bit master key in the macOS Data Protection Keychain (`AfterFirstUnlockThisDeviceOnly`). Sensitive-only encryption is the default encryption mode; all-item encryption is optional. Encrypted text is stored as ciphertext BLOB data, while image, thumbnail, PDF, and rich payload bytes are encrypted before disk write and decrypted only on demand. Decrypted thumbnail caches are invalidated on lock/private-mode changes.

Metadata such as item type, dates, pin state, sizes, hashes, source bundle identifier, logical filenames, and record counts remains visible in SQLite. Full-database encryption is not claimed.

Automatic lock supports inactivity intervals, screen lock, Touch ID where available, and the Mac login credential through LocalAuthentication. A locked app hides previews, rejects restoration, and clears decrypted caches.

Logging uses `os.Logger` and records only operation type/status, anonymized identifiers, error category, timing, and migration version. Clipboard text, secret values, decrypted data, raw image/PDF bytes, and unnecessary full paths are never logged.

## Retention and deletion

Background cleanup enforces the unpinned item count, general age, image age, and total managed-storage limit. Pinned items are preserved. Database changes are transactional; associated images, image groups, thumbnails, PDFs, and rich payloads are removed and thumbnail cache entries are invalidated.

Clear History rotates the encryption master key after removing records/assets, providing cryptographic erasure for content encrypted under that key. File removal and cache clearing are best effort. APFS snapshots, SSD wear levelling, backups, and filesystem internals mean physical overwrite cannot be guaranteed.

## Export and import

Exports support metadata-only JSON, a full unencrypted archive after explicit warning, or a password-protected archive. Password archives derive a key with PBKDF2-HMAC-SHA256 (200,000 rounds) and seal the payload with AES-GCM. Temporary sensitive items are never exported; images and file references can be excluded.

Imports validate the archive version, total size, item count, asset names, and record structure; reject traversal names; and merge through duplicate detection and prepared storage writes. Imports never execute SQL from an archive and do not overwrite current history silently.

## Performance observations

Measurements from the automated macOS test host on 2026-07-18 (temporary local SQLite databases, Release-capable host; timings vary by hardware and filesystem):

| Items | SQLite write | SQLite read |
|---:|---:|---:|
| 100 | 8.031 ms | 1.972 ms |
| 500 | 12.123 ms | 6.038 ms |
| 1,000 | 16.355 ms | 6.699 ms |
| 5,000 | 46.272 ms | 19.129 ms |

For 5,000 items, ViewModel load measured 45.386 ms, filtering 23.303 ms, and SwiftUI panel construction 16.309 ms. A live idle sample showed 0.0% CPU and approximately 46 MB RSS after format validation. These are observations, not guarantees. Scroll frame pacing, energy impact, and long-session heap growth still require manual Instruments profiling on target hardware.

## Known platform limitations and review boundary

- File bookmarks cannot make deleted files, disconnected volumes, or revoked permissions available; those rows display a missing/unavailable state.
- Pasteboard providers decide which representations are exposed. Restoring multiple independent image objects is best effort within AppKit pasteboard semantics.
- Quick Look support depends on the installed system preview generator.
- Native Carbon hotkey registration may not report that another process already owns the same key combination; actual shortcut delivery is the final authority.
- Secret detection is deliberately conservative but not perfect.
- Keychain encryption and Touch ID require a properly signed app and an interactive user session. An unsigned command-line build fails closed.
- Best-effort deletion cannot promise physical erasure on APFS/SSD media.
- The project does not include cloud synchronization, App Store packaging, notarization, or production distribution.

Before production distribution, perform an independent security review of secret heuristics, cryptographic lifecycle, import fuzzing, Keychain entitlements, bookmark scope behavior, and privacy logging; then profile with Instruments and verify Touch ID, screen lock, launch at login, menu bar interaction, and global-shortcut conflicts on supported macOS versions.
