# ClipboardHistory 1.0.0-beta.5

This Community beta adds a compact, native Control Center and a reusable wider window backed by the same feature controllers. Open in Window preserves Clipboard selection/search and the Notes draft. Clipboard search opens from the magnifier, focuses immediately and clears when closed. Notes distinguishes unsaved edits from a completed save; System Monitor starts with a numeric summary and loads charts on demand. Menu-bar customization immediately reflects placement and click-action changes.

Native popover animation remains enabled. SwiftUI transitions use a shared 140 ms policy and respect Reduce Motion; Reduce Transparency uses an opaque background. Shared metric sampling follows detail/menu-bar/Control Center demand at 1/2/5 seconds, doubles noncritical intervals in Low Power Mode and stops without consumers. Browser heartbeat timers stop when idle, and unchanged Chromium acknowledgements no longer cause a message loop.

Reliability fixes preserve Clear History recovery copies after rollback failure, calculate quotas after retention, invalidate stale capture work across Clear/privacy/shutdown, retain UI and pasteboard identity after failed deletion, and clean up failed imports. Browser commands are delivered to their source browser; resetting audio also clears saved preferences for closed applications. Keyboard handling respects editing, window, menu and modal context. Storage errors retain Settings and retry access.

The separate test host isolates storage, pasteboard, defaults, login items, input control and browser services. Its stubs do not constitute native hardware acceptance. Current development and UI evidence and remaining acceptance work are recorded in [Native Experience Implementation](NATIVE_EXPERIENCE_IMPLEMENTATION.md).

The release is arm64-only for macOS 14.2 or later, self-signed and not Apple-notarized. Browser audio, physical CoreAudio behavior, sensors, Accessibility input tools, VoiceOver, multi-display/notch layout, the external macOS matrix, native frame timing and the eight-hour soak retain the boundaries in [Known Limitations](KNOWN_LIMITATIONS.md). This is a public prerelease, not a production-stable release.

The GitHub assets include signed ZIP/DMG files, the Chromium extension ZIP, SHA-256 checksums, an SPDX SBOM, the designated requirement and the public signing-certificate fingerprint. Homebrew uses the same ZIP and checksum.
