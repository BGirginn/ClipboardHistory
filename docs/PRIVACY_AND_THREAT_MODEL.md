# Privacy and threat model

## Protected assets

Clipboard text, rich payloads, images, PDFs, user-visible titles, tags, collection names, OCR text, QR results, and detected colors are treated as private local data. Encrypted records use AES-GCM. A missing, denied, or unreadable master key stops recording and presents recovery; plaintext fallback is forbidden.

## Visible metadata

Item type, timestamps, byte sizes, content hashes, source bundle identifier, pin/use state, logical managed filenames, and record counts remain visible in SQLite. ClipboardHistory does not claim full-database encryption or protection from a process already running as the logged-in user with equivalent filesystem access.

## Inputs and boundaries

Pasteboard providers, archives, file URLs/bookmarks, HTML, RTF, PDF, and image decoders are untrusted inputs. Managed filenames reject traversal, separators, NUL, and unreasonable length. Archives enforce authenticated encryption, version, count and size limits, path validation, per-record and per-asset hashes, and atomic staging. HTML is sanitized and never executed.

The app intentionally has no networking, telemetry, analytics, account, sync, remote preview, or AI service. OCR and QR recognition use on-device Apple frameworks. Static checks fail on production network APIs and URL literals.

## Keychain and signing

Apple Development builds use Data Protection Keychain. Community builds use the login Keychain because a stable community signing requirement is needed across upgrades. Community builds must be signed by the same offline-held self-signed certificate and have no unauthorized keychain access-group entitlement. A certificate fingerprint is required in release notes.

The community beta is not Apple-trusted or notarized. Documentation may explain macOS's visible Open Anyway flow, but installers and scripts must never delete quarantine metadata or call `xattr` to suppress Gatekeeper.

## Non-goals

ClipboardHistory cannot prevent another local process with suitable privileges from reading the live system clipboard, defeat a compromised OS account, guarantee physical erasure on APFS/SSD media, restore deleted source files, or make heuristic secret detection infallible.
