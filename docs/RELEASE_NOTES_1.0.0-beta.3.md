# ClipboardHistory 1.0.0-beta.3

ClipboardHistory is now a modular macOS menu-bar Control Center. Clipboard History and Notes are joined by Input Tools, a live System Monitor, configurable menu-bar metrics, and an experimental Audio Mixer.

## Highlights

- Pin individual features or selected system metrics to the menu bar, or keep them inside one Control Center item.
- Create encrypted notes with automatic save and independent Keychain protection.
- Inspect CPU, memory, network, disk, and verified temperature data without persistent metric logging.
- Use Keyboard Cleaning and Scroll Reverse from the shared input-event infrastructure.
- Opt into experimental per-application audio gain and supported Chromium/Safari tab controls.
- Benefit from schema-v6 open Clipboard storage with one-time legacy encrypted-record migration, transactional deletion, stricter archive validation, and authenticated sensitive-content actions.

## Distribution and privacy

This is an arm64-only Community prerelease for macOS 14.2 or later. It is self-signed and not Apple-notarized. Clipboard and Notes data stay local; system samples and browser tab metadata are memory-only, and audio is not recorded.

The Audio Mixer is hidden on fresh profiles because signed multi-browser and physical device-switch validation remains incomplete. The 95.80% coverage capture meets the Community beta's 95% aggregate gate; native CoreAudio/event-tap lifecycle and remaining UI/error paths are tracked coverage debt. External OS, Accessibility, VoiceOver, multi-display, Instruments, and long-soak gaps are listed in [Known Limitations](KNOWN_LIMITATIONS.md).
