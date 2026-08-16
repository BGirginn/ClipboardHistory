# Known limitations

- `v1.0.0-beta.4` is a Community prerelease, not a production or notarized release.
- The Community application is self-signed. Gatekeeper can require Finder Control-click → Open or System Settings → Privacy & Security → Open Anyway on first launch.
- Only macOS 26.5 arm64 has executed locally. The complete macOS 14/15/26 external OS matrix has not been recorded for this release.
- Encrypted Notes and one-time migration of legacy encrypted Clipboard records depend on login-Keychain access and the stable signing identity. Current open Clipboard storage does not require Keychain access.
- Direct paste, Keyboard Cleaning Mode, and Scroll Reverse require Accessibility permission; ordinary capture, copy, restore, notes, and Paste As do not.
- Keyboard Cleaning Mode intentionally leaves mouse input available and automatically unlocks after 60 seconds; Secure Input or system policy can prevent the event tap from starting.
- Public CoreGraphics fields distinguish line-based from pixel-based scrolling, not a guaranteed device model. The UI therefore cannot promise brand/model-specific routing, and external wheel-mouse behavior must be checked with the intended hardware.
- Per-application audio uses macOS 14.2+ Core Audio process taps and requires System Audio Recording approval. A revoked permission, output-device loss, or pipeline failure returns the application to its native audio path; physical multi-application and device-switch acceptance is still required before release.
- Chromium tab gain requires the bundled unpacked extension and a user-initiated `Miksere Ekle` action for every captured tab. Safari can control only directly accessible HTML media elements; DRM, Web Audio, protected browser pages, and denied site access are intentionally not represented as controllable tabs.
- Degree temperatures use validated AppleSMC keys or Apple Silicon HID CPU/SoC die sensors. Sensor names vary by SoC; unrecognized hardware shows `Unavailable` instead of estimating a value. The Apple M4 path has been read locally, but comparison against a second trusted sensor tool remains a release acceptance step.
- OCR and QR accuracy depends on image quality and Apple's on-device frameworks.
- File bookmarks cannot restore deleted files, disconnected volumes, or revoked access.
- Secret detection is heuristic and can have false positives or negatives.
- APFS snapshots, backups, SSD wear levelling, and external backups prevent a physical-erasure guarantee.
- Full clean-user manual UI, VoiceOver/focus, high-contrast, Reduce Motion/Transparency, 200% scaling, small/multiple-display, Instruments, and eight-hour soak evidence is not complete. The release is explicitly labelled beta for these remaining validation gaps.
