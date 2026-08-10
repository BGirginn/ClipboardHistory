# Privacy and threat model

## Protected assets

Clipboard text, rich payloads, images, PDFs, note titles and bodies, user-visible titles, tags, collection names, OCR text, QR results, and detected colors are treated as private local data. Encrypted records use AES-GCM. Clipboard history and notes use separate login-Keychain accounts so clearing history and rotating its key does not invalidate notes. A missing, denied, or unreadable required key fails closed; plaintext fallback is forbidden.

## Visible metadata

Item type, timestamps, byte sizes, content hashes, source bundle identifier, pin/use state, logical managed filenames, note UUID/timestamps, and record counts remain visible in SQLite. Note titles and bodies do not. ClipboardHistory does not claim full-database encryption or protection from a process already running as the logged-in user with equivalent filesystem access.

## Inputs and boundaries

Pasteboard providers, archives, file URLs/bookmarks, HTML, RTF, PDF, and image decoders are untrusted inputs. Managed filenames reject traversal, separators, NUL, and unreasonable length. Archives enforce authenticated encryption, version, count and size limits, path validation, per-record and per-asset hashes, and atomic staging. HTML is sanitized and never executed.

The app intentionally has no telemetry, analytics, account, sync, remote preview, or AI service. OCR and QR recognition use on-device Apple frameworks. The Chromium and Safari companion extensions run only inside their browser permission boundaries; they exchange versioned, size-limited control messages with the local application and do not upload browsing data.

System metric samples stay in a time-bounded in-memory ring buffer and are not added to SQLite, archives, logs, or telemetry. Audio processing is real-time and memory-only: samples are not recorded, logged, analyzed, or persisted. Only per-application gain preferences keyed by bundle identifier are stored. Browser tab titles, URLs, identifiers, incognito state, and volume state are memory-only; incognito tabs are rejected by default. Safari lists only pages where the extension can directly modify non-DRM HTML media elements. Chromium tab capture starts only after the user invokes the extension action for that tab.

Input Tools use one local CoreGraphics session event tap after explicit macOS Accessibility approval. Keyboard Cleaning discards key-down, key-up, modifier, and media-key events while active; it does not record, inspect, persist, or log typed content. Mouse and scroll events remain available, the mode automatically releases after 60 seconds, and lock/sleep/termination paths stop it. Scroll Reverse changes only enabled vertical/horizontal delta fields on the incoming event and preserves its phase, momentum, timestamp, and source; it never stores or logs event values or application content. Missing or revoked permission leaves native input unchanged.

## Keychain and signing

Every runnable configuration uses one classic login-Keychain service with separate history and note accounts because a stable signing requirement is needed across upgrades. Builds must use the same self-signed certificate and have no keychain access-group entitlement. This requires no Apple account or provisioning profile. A certificate fingerprint is required in release notes.

The community beta is not Apple-trusted or notarized. Documentation may explain macOS's visible Open Anyway flow, but installers and scripts must never delete quarantine metadata or call `xattr` to suppress Gatekeeper.

## Non-goals

ClipboardHistory cannot prevent another local process with suitable privileges from reading the live system clipboard, defeat a compromised OS account, guarantee physical erasure on APFS/SSD media, restore deleted source files, or make heuristic secret detection infallible.
