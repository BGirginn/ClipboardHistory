# Privacy and threat model

## Protected assets

Clipboard text, rich payloads, images, PDFs, note titles and bodies, user-visible titles, tags, collection names, OCR text, QR results, and detected colors are treated as private local data. Clipboard history uses open local storage; it no longer depends on Keychain availability. Note titles and bodies remain AES-GCM encrypted with their separate login-Keychain account.

## Visible metadata

Clipboard content and metadata, including file paths and bookmarks, are stored locally without encryption. Note UUIDs and timestamps are visible in SQLite, while note titles and bodies are not plaintext. ClipboardHistory does not claim that Clipboard history is protected from another process with equivalent access to the logged-in user's files.

## Inputs and boundaries

Pasteboard providers, archives, file URLs/bookmarks, HTML, RTF, PDF, and image decoders are untrusted inputs. Capture accepts at most 32 pasteboard items, 1 MiB text, 8 MiB RTF/HTML, 64 MiB per binary representation, 128 MiB total, and 100 MP/16,384 pixels per image side. Managed filenames reject traversal, separators, NUL, and unreasonable length. Archives enforce authenticated encryption, version, count and size limits, path validation, per-record and per-asset hashes, and transactional database commit. HTML is parsed with libxml2 network access disabled and serialized through an element, attribute, and URL-scheme allowlist.

The app intentionally has no telemetry, analytics, account, sync, remote preview, or AI service. OCR and QR recognition use on-device Apple frameworks. The Chromium and Safari companion extensions run only inside their browser permission boundaries; they exchange versioned, size-limited control messages with the local application and do not upload browsing data. The experimental bridge uses an embedded XPC service that checks the caller UID, live code validity, allowlisted bundle identifier, and equality with the service's signing certificate before accepting a connection. Audio Mixer remains hidden for fresh profiles until signed multi-browser runtime validation is complete.

System metric samples stay in a time-bounded in-memory ring buffer and are not added to SQLite, archives, logs, or telemetry. Audio processing is real-time and memory-only: samples are not recorded, logged, analyzed, or persisted. Only per-application gain preferences keyed by bundle identifier are stored. Browser tab titles, URLs, identifiers, incognito state, and volume state are memory-only; incognito tabs are rejected by default. Safari lists only pages where the extension can directly modify non-DRM HTML media elements. Chromium tab capture starts only after the user invokes the extension action for that tab.

Input Tools use one local CoreGraphics session event tap after explicit macOS Accessibility approval. Keyboard Cleaning discards key-down, key-up, modifier, and media-key events while active; it does not record, inspect, persist, or log typed content. Mouse and scroll events remain available, the mode automatically releases after 60 seconds, and lock/sleep/termination paths stop it. Scroll Reverse changes only enabled vertical/horizontal delta fields on the incoming event and preserves its phase, momentum, timestamp, and source; it never stores or logs event values or application content. Missing or revoked permission leaves native input unchanged.

## Keychain and signing

Notes use the classic login Keychain because a stable signing requirement is needed across upgrades. Clipboard history no longer uses a Keychain key. Builds keep the same self-signed certificate and have no keychain access-group entitlement. This requires no Apple account or provisioning profile. A certificate fingerprint is required in release notes.

Application Lock is a local presentation and interaction boundary, not disk encryption. Clipboard recording pauses while the app is locked so new plaintext records cannot be persisted behind a locked interface. Notes remain encrypted independently.

The community beta is not Apple-trusted or notarized. Documentation may explain macOS's visible Open Anyway flow, but installers and scripts must never delete quarantine metadata or call `xattr` to suppress Gatekeeper.

## Non-goals

ClipboardHistory cannot prevent another local process with suitable privileges from reading the live system clipboard, defeat a compromised OS account, guarantee physical erasure on APFS/SSD media, restore deleted source files, or make heuristic secret detection infallible.
