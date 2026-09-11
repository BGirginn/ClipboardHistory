# CoreDeck 1.0.0-beta.6

ClipboardHistory is now CoreDeck. Finder, the menu bar, windows, permission text, and the Safari and Chromium companion extensions use the CoreDeck name. Clipboard History remains the name of the clipboard module.

This is a compatibility-preserving rebrand. The application continues to use the `com.brgirgin.ClipboardHistory` bundle identifier, existing helper and browser-service identifiers, `~/Library/Application Support/ClipboardHistory`, existing preferences, the Notes Keychain service, and the stable self-signed `ClipboardHistory Community Beta` identity. Existing clipboard data, encrypted Notes, settings, login-item state, and browser-audio connections are therefore expected to remain available across the upgrade.

The main application is now `CoreDeck.app` with a `CoreDeck` executable. New archive suggestions use `CoreDeck.clipboardarchive` or `CoreDeck-Encrypted.clipboardarchive`; existing archive versions remain importable. The Chromium package is named `CoreDeck-Chromium-Audio-1.0.0-beta.6.zip`.

Homebrew compatibility is retained through `brew install --cask clipboardhistory`. A normal Cask upgrade replaces the old managed `ClipboardHistory.app` with `CoreDeck.app`. Before a manual installation, quit and remove or move aside an unmanaged `/Applications/ClipboardHistory.app`; user data stored under Application Support is separate and remains in place.

This Community beta is arm64-only for macOS 14.2 or later, self-signed, and not Apple-notarized. It must be built from the exact release commit with the stable Community identity. The release assets include ZIP and DMG packages, the Chromium extension ZIP, SHA-256 checksums, an SPDX SBOM, the designated requirement, and the public signing-certificate fingerprint. Remaining native and physical acceptance boundaries are documented in [Known Limitations](KNOWN_LIMITATIONS.md).
