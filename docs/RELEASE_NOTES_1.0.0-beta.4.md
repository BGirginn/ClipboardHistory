# ClipboardHistory 1.0.0-beta.4

This Community beta completes the new Control Center and settings experience. The application-wide and feature-specific settings now use two compact icon shelves, while common Clipboard actions such as Private Mode, retention cleanup, and Clear History are available from Clipboard itself. The obsolete Application Lock feature and per-core CPU list have been removed.

Menu-bar behavior has been rebuilt around independent feature items and configurable metrics. Text metrics use stable single-line widths and monospaced digits, network and disk rates are displayed in bytes per second, zero values render as `0`, and CPU/RAM/network/disk/temperature visibility and style can be selected. The main Control Center icon can now be hidden safely: ClipboardHistory becomes available in the Dock and opens the same interface in a normal resizable window. Popovers anchor to the status item that initiated the action.

Audio Mixer now resolves user-facing application names such as Brave Browser and Spotify instead of exposing helper process or PID-style identities. Accessibility authorization is shared by Direct Paste, Keyboard Cleaning, and Scroll Reverse, so macOS is prompted at most once per application session; later attempts show the existing in-app route to Accessibility Settings instead of producing duplicate system prompts.

Clipboard list rows and thumbnails were simplified, and history cleanup and privacy actions were moved closer to the content they affect. The release also restores GitHub runner compatibility by installing the command-line dependency used by repository quality scripts when runner images do not provide it.

The release remains arm64-only for macOS 14.2 or later, self-signed, and not Apple-notarized. The broader beta limitations documented in [Known Limitations](KNOWN_LIMITATIONS.md) remain unchanged.
