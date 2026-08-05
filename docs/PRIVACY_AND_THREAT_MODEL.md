# Privacy and threat model

## Protected assets

Clipboard text, rich payloads, images, PDFs, note titles and bodies, user-visible titles, tags, collection names, OCR text, QR results, and detected colors are treated as private local data. Encrypted records use AES-GCM. Clipboard history and notes use separate login-Keychain accounts so clearing history and rotating its key does not invalidate notes. A missing, denied, or unreadable required key fails closed; plaintext fallback is forbidden.

## Visible metadata

Item type, timestamps, byte sizes, content hashes, source bundle identifier, pin/use state, logical managed filenames, note UUID/timestamps, and record counts remain visible in SQLite. Note titles and bodies do not. ClipboardHistory does not claim full-database encryption or protection from a process already running as the logged-in user with equivalent filesystem access.

## Inputs and boundaries

Pasteboard providers, archives, file URLs/bookmarks, HTML, RTF, PDF, and image decoders are untrusted inputs. Managed filenames reject traversal, separators, NUL, and unreasonable length. Archives enforce authenticated encryption, version, count and size limits, path validation, per-record and per-asset hashes, and atomic staging. HTML is sanitized and never executed.

The app intentionally has no networking, telemetry, analytics, account, sync, remote preview, or AI service. OCR and QR recognition use on-device Apple frameworks. Static checks fail on production network APIs and URL literals.

## Keychain and signing

Every runnable configuration uses one classic login-Keychain service with separate history and note accounts because a stable signing requirement is needed across upgrades. Builds must use the same self-signed certificate and have no keychain access-group entitlement. This requires no Apple account or provisioning profile. A certificate fingerprint is required in release notes.

The community beta is not Apple-trusted or notarized. Documentation may explain macOS's visible Open Anyway flow, but installers and scripts must never delete quarantine metadata or call `xattr` to suppress Gatekeeper.

## Non-goals

ClipboardHistory cannot prevent another local process with suitable privileges from reading the live system clipboard, defeat a compromised OS account, guarantee physical erasure on APFS/SSD media, restore deleted source files, or make heuristic secret detection infallible.
