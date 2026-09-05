# ClipboardHistory 1.0.0-beta.5

This Community beta completes the native topbar stabilization work. Visible System Monitor metrics migrate to independently movable items: CPU and RAM use compact two-line labels, while temperature shows only its localized value without an icon or redundant label. Metric sampling remains centralized and status-item identities remain stable as values change.

Popover and window demand ownership, Clipboard capture continuity, Keyboard Cleaning start/stop behavior, Audio Mixer application identity, System Monitor accounting, temperature sourcing, and compact Control Center and Settings layouts received the broader fixes listed in the changelog.

Browser audio now uses one on-demand LaunchAgent Mach service shared by the main app, Chromium native host, and bundled Safari extension. The bridge retains caller UID, live signature, bundle allowlist, certificate, schema, and message-size validation. Chromium resources are also attached as a standalone ZIP for manual unpacked installation; no browser store publication is included.

The release remains arm64-only for macOS 14.2 or later, self-signed, and not Apple-notarized. Browser audio, physical CoreAudio behavior, sensors, Accessibility input tools, multi-display/notch layout, and the external macOS matrix retain the acceptance boundaries documented in [Known Limitations](KNOWN_LIMITATIONS.md).
