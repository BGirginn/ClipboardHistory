<p align="center">
  <img src="ClipboardHistory/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="128" height="128" alt="ClipboardHistory app icon">
</p>

<h1 align="center">ClipboardHistory</h1>

<p align="center">
  A private, native clipboard manager for the macOS menu bar.
</p>

<p align="center">
  <a href="README_TR.md">Türkçe</a>
</p>

ClipboardHistory keeps searchable clipboard history locally on your Mac. It is written in Swift 6 with SwiftUI and AppKit and has no networking, telemetry, account system, cloud service, or third-party runtime dependency.

## Current status

- Current beta candidate: `1.0.0-beta.1` (`1.0.0`, build `10001`)
- Supported platform: Apple silicon (`arm64`) with macOS 14 Sonoma or later
- The source on `main` is public and current
- A GitHub Release and Homebrew Cask have **not** been published yet
- The Community build is self-signed and is not Apple-notarized

Homebrew installation is therefore not available yet. Until the first release is published, the app can be built from source using the steps below.

## Features

- Text, URL, email, source-code, rich-text, image, PDF, and file/folder history
- Search, type/date/source filters, sorting, collections, tags, pinned items, and snippets
- Copy, restore, paste to the active app, Paste As, Quick Look, drag and drop, and bulk actions
- FIFO/LIFO Paste Stack and keyboard-oriented navigation
- System, Light, and Dark appearance options
- Private Mode, temporary recording pause, app exclusions, and Ignore Next Copy toggle
- Optional application lock using Touch ID or the Mac login password
- Local secret detection and temporary handling for sensitive clipboard items
- AES-GCM history encryption with a Keychain-backed key and no plaintext fallback
- Password-protected local archive export/import
- Local Vision OCR, QR recognition, and color analysis
- English and Turkish localization

## Privacy model

ClipboardHistory reads only clipboard changes exposed through `NSPasteboard`. It does not watch the Desktop or other folders and does not send clipboard content over the network.

History is stored locally in SQLite. Encryption keys live in the macOS login Keychain; Keychain failures are handled fail-closed. The optional application lock is a viewing and interaction privacy layer and is disabled by default.

See [Privacy and Threat Model](docs/PRIVACY_AND_THREAT_MODEL.md) and [Known Limitations](docs/KNOWN_LIMITATIONS.md) for the full boundary.

## Build from source

Requirements:

- Apple silicon Mac
- macOS 14 or later
- Xcode with Swift 6 support

Clone the repository and create the local self-signed Community identity. This does not require a paid Apple Developer account:

```sh
git clone https://github.com/BGirginn/ClipboardHistory.git
cd ClipboardHistory
scripts/create-community-signing-identity.sh
scripts/verify-community-signing.sh
```

Build and launch the Community configuration:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration CommunityRelease \
  -destination 'generic/platform=macOS' \
  -derivedDataPath .build/LocalRelease \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='ClipboardHistory Community Beta' \
  build

open .build/LocalRelease/Build/Products/CommunityRelease/ClipboardHistory.app
```

The certificate private key remains in the user's login Keychain and must never be committed.

## Usage

ClipboardHistory runs as a menu-bar application and does not appear in the Dock. Click the clipboard icon or press `Command-Shift-V` to open the panel.

Clipboard history and managed assets are stored under:

```text
~/Library/Application Support/ClipboardHistory/
```

Direct paste requests require macOS Accessibility permission. Clipboard capture, panel access, and the global shortcut do not require that permission.

## Development

Compile without signing:

```sh
xcodebuild \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Project documentation:

- [Architecture](docs/ARCHITECTURE.md)
- [Testing](docs/TESTING.md)
- [Performance](docs/PERFORMANCE.md)
- [Distribution](docs/DISTRIBUTION.md)
- [Security Policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## Distribution

The repository currently contains the source and reproducible Community packaging scripts. The first immutable GitHub Release and the `BGirginn/homebrew-tap` Cask will be prepared separately. Do not use or advertise a `brew install` command until those public resources exist.

## License

ClipboardHistory is available under the [MIT License](LICENSE).
