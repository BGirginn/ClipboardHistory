# CoreDeck 1.0.0-beta.8

This release completes the ClipboardHistory-to-CoreDeck product identity migration.

- Renamed the app bundle and executable to `CoreDeck.app` and `CoreDeck`.
- Migrates existing storage, preferences, launch-at-login state, and Keychain keys with fail-closed behavior; old data remains available for recovery.
- Updated the browser audio bridge identifiers and Chromium extension version.
- Keeps launch-at-login migration retryable if macOS rejects helper registration.
- Renamed the Homebrew Cask to `coredeck` and added the old-token migration map.
- Community artifacts remain self-signed and are not Apple-notarized.

The release remains a beta. Full clean-user migration, physical macOS version coverage, Energy Log profiling, and the eight-hour soak have not been completed.
