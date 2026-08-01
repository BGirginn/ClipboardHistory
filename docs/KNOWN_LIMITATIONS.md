# Known limitations

- `v1.0.0-beta.1` is a Community prerelease, not a production or notarized release.
- The Community application is self-signed. Gatekeeper can require Finder Control-click → Open or System Settings → Privacy & Security → Open Anyway on first launch.
- Only macOS 26.5 arm64 has executed locally. The complete macOS 14/15/26 external OS matrix has not been recorded for this release.
- Login-Keychain access depends on the stable self-signed identity and an interactive user session; unsigned builds fail closed where appropriate.
- Direct paste requires Accessibility permission; ordinary capture, copy, restore, and Paste As do not.
- OCR and QR accuracy depends on image quality and Apple's on-device frameworks.
- File bookmarks cannot restore deleted files, disconnected volumes, or revoked access.
- Secret detection is heuristic and can have false positives or negatives.
- APFS snapshots, backups, SSD wear levelling, and external backups prevent a physical-erasure guarantee.
- Full clean-user manual UI, VoiceOver/focus, high-contrast, Reduce Motion/Transparency, 200% scaling, small/multiple-display, Instruments, and eight-hour soak evidence is not complete. The release is explicitly labelled beta for these remaining validation gaps.
