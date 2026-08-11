---
name: clipboardhistory-change-safety
description: Implement or review ClipboardHistory code changes while preserving repository architecture, tests, privacy, data integrity, and macOS behavior. Use for general feature work, refactors, or bug fixes that cross multiple modules. Do not use instead of a more specific storage/security, performance, menu-bar, audio, or release skill when one clearly applies.
---

# ClipboardHistory Change Safety

1. Read the root `AGENTS.md`.
2. Inspect `git status` before edits.
3. Read the affected implementation, its protocol/system adapter, existing tests, and relevant docs.
4. Build a short dependency/data-flow map before changing code.
5. Search for existing helpers and patterns; do not create a parallel abstraction without proving the existing one cannot serve the requirement.
6. Preserve:
   - shared feature state/controllers,
   - static first-party feature registry,
   - strict concurrency,
   - test isolation,
   - existing storage/security boundaries,
   - centralized System Monitor sampling.
7. For behavior changes, add a regression test before or with the implementation.
8. Run targeted tests first:
   `scripts/run-development-tests.sh <test-identifier>`
9. Run:
   `scripts/verify-static-quality.sh`
10. Run broader tests when the blast radius warrants it:
    `scripts/run-development-tests.sh`
11. Inspect the final diff and classify every changed file as required or incidental.
12. Report:
    - root cause or design reason,
    - files changed,
    - tests actually run,
    - validation that remains macOS/manual,
    - any invariant or compatibility risk.

Escalate to the specific skill when touching:
- storage/security/privacy,
- System Monitor/performance,
- menu-bar/AppKit lifecycle,
- Audio Mixer/CoreAudio/browser bridge,
- release/signing/evidence.
