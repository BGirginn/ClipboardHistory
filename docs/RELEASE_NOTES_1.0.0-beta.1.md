# ClipboardHistory 1.0.0-beta.1

The first public Community beta of ClipboardHistory is available for Apple silicon Macs running macOS 14 Sonoma or later.

## Install with Homebrew

```sh
brew tap BGirginn/tap
brew trust BGirginn/tap
brew install --cask clipboardhistory
```

Homebrew 6 requires the explicit trust command for third-party taps. If ClipboardHistory was previously copied into `/Applications` manually, quit it and move that existing app bundle out of `/Applications` before running the Cask install. Existing clipboard history remains under Application Support.

The ZIP and DMG are also attached to this release. `SHA256SUMS`, the SPDX SBOM, designated requirement, and signing-certificate fingerprint are published alongside them.

## Important signing notice

This Community beta is self-signed and is not Apple-notarized. If macOS blocks first launch, open Applications in Finder, Control-click ClipboardHistory, choose **Open**, and confirm. The same approval is available under System Settings → Privacy & Security. Do not remove quarantine with `xattr`.

## Highlights

- Native Swift 6 menu-bar clipboard history with local SQLite persistence
- Text, rich text, images, PDFs, files/folders, search, collections, tags, snippets, and Paste Stack
- AES-GCM history encryption with a login-Keychain-backed master key and fail-closed errors
- Optional Touch ID or Mac-login application lock, Private Mode, pause, exclusions, and Ignore Next Copy toggle
- Direct paste, Paste As, Quick Look, drag and drop, import/export, OCR, QR, and color analysis
- System, Light, and Dark themes plus English and Turkish localization
- Apple silicon-only build with a macOS 14 minimum and a new black ClipboardHistory app icon

This prerelease has known external OS, accessibility/visual, Instruments, and long-soak validation gaps. Review the [known limitations](https://github.com/BGirginn/ClipboardHistory/blob/v1.0.0-beta.1/docs/KNOWN_LIMITATIONS.md) before installing.
