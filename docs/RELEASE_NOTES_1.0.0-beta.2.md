# ClipboardHistory 1.0.0-beta.2

This Community beta updates the menu-bar interaction for Apple silicon Macs running macOS 14 Sonoma or later.

## Install or upgrade with Homebrew

```sh
brew tap BGirginn/tap
brew trust BGirginn/tap
brew update
brew upgrade --cask clipboardhistory
```

For a first installation, replace the final command with `brew install --cask clipboardhistory`. If ClipboardHistory was previously copied into `/Applications` manually, quit it and move that unmanaged application bundle out of `/Applications` before installing the Cask. Clipboard history remains stored separately under Application Support.

## Changes since beta.1

- Removed the panel search bar and its Command-F focus path.
- Added a native right-click menu to the menu-bar icon with an explicit Quit action; right-clicking alone no longer closes the application.
- Kept the native opening animation while preloading and laying out the SwiftUI panel before presentation, eliminating the frame-by-frame opening stutter.
- Documented the Homebrew 6 trust step and the migration from a manually installed application bundle.

## Signing notice

The arm64 ZIP and DMG are signed with the stable self-signed `ClipboardHistory Community Beta` identity and are not Apple-notarized. If macOS blocks first launch, open Applications in Finder, Control-click ClipboardHistory, choose **Open**, and confirm. The same approval is available under System Settings → Privacy & Security. Do not remove quarantine with `xattr`.

This update received focused menu-bar regression tests and a signed CommunityRelease build. The broader external OS, accessibility/visual, Instruments, and long-soak gaps remain disclosed in the [known limitations](https://github.com/BGirginn/ClipboardHistory/blob/v1.0.0-beta.2/docs/KNOWN_LIMITATIONS.md).
