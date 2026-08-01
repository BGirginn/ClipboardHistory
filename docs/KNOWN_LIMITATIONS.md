# Known limitations

- No `v1.0.0-beta.1` artifact, GitHub Release, or Homebrew Cask is published while release gates are incomplete.
- The Community build is intended to use a self-signed identity and is not Apple-notarized; Gatekeeper will show a warning.
- Only macOS 26.5 arm64 has executed locally. macOS 14, 15, and 26 arm64 CI/VM evidence is required for the release commit.
- Login-Keychain access depends on the stable self-signed identity and an interactive user session; unsigned tests use isolated keys and fail closed where appropriate.
- Direct paste requires Accessibility permission; ordinary copy and Paste As do not.
- OCR and QR accuracy depends on image quality and Apple's on-device frameworks.
- File bookmarks cannot restore deleted files, disconnected volumes, or revoked access.
- Secret detection is heuristic and can have false positives or negatives.
- APFS snapshots, backups, and SSD wear levelling prevent a physical-erasure guarantee.
- Signed UI automation, the full visual/VoiceOver matrix, Instruments, eight-hour soak, expanded media fuzz corpus, and 100% line coverage remain beta blockers.
