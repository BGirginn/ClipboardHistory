# CoreDeck 1.0.0-beta.7

This Community beta fixes three everyday controls:

- Settings now opens at a usable size, including after an older small window frame was saved.
- Clipboard can be moved directly from the Drawer to its own always-visible menu-bar item.
- Audio Mixer gain changes last only for the current application process. A newly launched application no longer inherits a previous process's zero gain.

Install or upgrade with `brew tap BGirginn/tap`, `brew trust BGirginn/tap`, then `brew install --cask clipboardhistory` or `brew upgrade --cask clipboardhistory`. The Cask token and existing data identities stay unchanged. The package installs `CoreDeck.app` on Apple silicon macOS 14.2 or later. A manually installed old `/Applications/ClipboardHistory.app` is not managed by Homebrew; quit and move it aside before installation without deleting its user data.

The Community app is self-signed, not Apple-notarized. Gatekeeper may require Finder Control-click → Open or System Settings → Privacy & Security → Open Anyway on first launch. The release includes the arm64 ZIP and DMG, Chromium audio extension, SHA-256 checksums, SPDX SBOM, source commit, designated requirement, and public signing-certificate fingerprint. It does not include private signing material.

Native and physical acceptance gaps, including the full supported-macOS matrix and external menu-bar item management, remain listed in [Known Limitations](https://github.com/BGirginn/ClipboardHistory/blob/main/docs/KNOWN_LIMITATIONS.md). This is a beta, not a stable release.
