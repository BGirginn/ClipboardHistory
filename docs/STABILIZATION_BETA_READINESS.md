# Stabilization beta readiness

Date: 2026-08-12

Candidate: `v1.0.0-beta.3` / build `10003`

Decision: **not yet approved for beta packaging or installation**

## Implemented in this worktree

- SQLite schema v6 migrates Clipboard content, private metadata, collection names, and assets to open local storage. Existing encrypted Clipboard records are decrypted once with their legacy key; Notes keep their independent AES-GCM storage.
- Clipboard deletion and Clear History distinguish database commit from residual cleanup, preserve Notes, clear collections and Clipboard backups, avoid any current Clipboard-Keychain dependency, and recover interrupted clear quarantines at startup.
- Normal quit waits for both Notes and pending Clipboard writes and cancels termination when either cannot be persisted.
- Metadata-only archives remove content-derived metadata, Notes, file references, and collections. Merge import prepares accepted records before one item/collection/note database transaction and removes rejected materialized assets.
- Sensitive details start redacted and use system authentication for reveal/copy/paste/preview/export boundaries. Quick Look uses `0700` directories, `0600` files, and startup orphan cleanup.
- Capture limits, PKCS#8 detection, stale rich-text invalidation, libxml2 `NONET` HTML allowlisting, full UTF-8 PBKDF2 password bytes, and zero-length random-buffer handling are implemented.
- CoreAudio discovery uses exact typed storage and byte-size validation, groups all process object IDs per application, validates Float32 stream formats, and restores native audio on replacement failure.
- Empty CoreAudio bundle identifiers now fall back to a PID-scoped identity instead of merging unrelated processes. Pipeline construction is injectable, and replacement failure, device mismatch, gain clamping, supported Float32 formats, and fail-open teardown have deterministic tests.
- Chromium extension installation is rooted through an injected Application Support boundary. Native-host manifests, XPC endpoint replies, message limits, tab namespaces, 128-tab cap, and volume clamping have isolated tests.
- Menu-bar configuration v3 adds memory, temperature, and rate formatting; empty metric groups cannot remove the last reachable status item. Audio Mixer is experimental and hidden for fresh profiles.
- System Monitor uses `active + wired + compressed` for Used memory and displays separate CPU, memory, network, and disk histories from the bounded in-memory ring buffer.

## Remaining blockers

- The browser bridge now uses an embedded XPC service. The listener accepts only the signed main app, login/native-host helper, and Safari extension bundle identifiers from the same signing certificate; messages remain versioned and capped at 256 KiB. Signed multi-browser runtime validation is still required, so browser audio remains experimental and hidden on fresh profiles.
- CoreAudio process-list and default-output changes are now event-driven with low-frequency active-pipeline reconciliation. Physical multi-app/device-switch fail-open evidence is still incomplete.
- Coverage capture passed 291 unit and 10 UI tests but the unchanged per-file/aggregate 100% gate failed at 95.76%. The threshold was not lowered; live CoreAudio tap lifecycle, event-tap lifecycle, and remaining UI/error paths remain a beta blocker.
- Signed Accessibility, keyboard cleaning, scroll reversal, browser extension, temperature comparison, macOS 14/15, VoiceOver, multi-display/notch, Instruments, and eight-hour soak gates have not yet been completed for this worktree.
- `v1.0.0-beta.3` / build `10003` was selected for external prerelease preparation. Packaging, publication, and installation evidence must be added only after those operations actually pass; mandatory coverage and physical acceptance gaps remain disclosed.

## Automated evidence from this worktree

- Unit/integration: 291 passed, 0 failed.
- UI automation under coverage: 10 passed, 0 failed after updating the Security-section assertion for the removed Encryption UI.
- ASan: 290 passed, 0 failed; TSan: 290 passed, 0 failed.
- Critical mutations: 7 killed, 0 survived, including locked capture and open-storage migration mutations.
- Optimized arm64 p95 performance benchmark passed.
- Debug, Release, and CommunityRelease architecture builds passed for the app, login helper, XPC service, and Safari extension with arm64-only output and macOS 14.2 minimum.
- Community-signed UI: 10 passed, 0 failed. The ad-hoc UI coverage run also passed 10 tests.
- ASan: 288 passed. TSan: 288 passed. No sanitizer diagnostics were emitted.
- Critical mutations: 7 killed, 0 survived.
- Debug, Release, and CommunityRelease: app, login helper, XPC service, and Safari extension are arm64-only with macOS 14.2 minimum.
- Static structure, localization, analyzer, release-secret/history scan, optimized arm64 p95 performance, and `git diff --check` passed.
- Coverage evidence: `/private/tmp/clipboardhistory-coverage-beta3-r3.rGSQ7P/evidence/Combined.xccovreport`; aggregate 95.02%, gate failed.

This document must be updated with command output and physical-test evidence before a beta readiness decision changes.
