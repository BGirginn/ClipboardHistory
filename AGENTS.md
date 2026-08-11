# ClipboardHistory — Codex Repository Guidance

## Purpose

ClipboardHistory is a native Apple-silicon macOS utility hub. It combines a modular Control Center with independently pinnable menu-bar tools, including Clipboard History, Notes, Input Tools, System Monitor, and Audio Mixer.

Treat privacy, data integrity, battery usage, and native macOS behavior as product requirements, not optional cleanup work.

## Instruction priority

1. System/developer instructions.
2. This `AGENTS.md`.
3. The repository's existing documentation and established code conventions.
4. The user's current request.

Never override a repository invariant merely to make a test pass.

## Before editing

- Inspect `git status`.
- Read the directly affected implementation, its protocols/adapters, relevant tests, and the closest architecture/security/testing documentation.
- Search for existing helpers before adding new abstractions.
- Identify whether the change crosses any of these boundaries:
  - Storage / SQLite / assets / migrations
  - Encryption / Keychain / sensitive content
  - Pasteboard identity / paste behavior
  - Menu-bar lifecycle / AppKit
  - System metrics / timers / IOKit / HID
  - CoreAudio / browser native messaging
  - Import / export / archive parsing
- If it does, use the matching repo skill under `.agents/skills`.

## Implementation rules

- Fix the root cause. Do not hide symptoms.
- Keep changes within the requested scope.
- Preserve the existing modular feature architecture and shared-controller model unless a change proves that architecture insufficient.
- Prefer existing protocols and dependency injection over new singletons.
- UI/AppKit mutations belong on the main actor.
- Do not create one polling loop or timer per UI consumer when a shared producer can serve them.
- Do not claim privacy, encryption, deletion, or exclusion guarantees that the implementation cannot enforce.
- A UI success state must not be committed before the underlying persistent/security operation succeeds.
- Never silently swallow failures that can leave user data on disk after the UI says it was deleted.
- Do not introduce `try!`, `as!`, new production `fatalError`, real credentials, certificates, private keys, absolute user paths, or production user data.
- Keep production Swift files within repository static-quality limits and follow the existing one-primary-type-per-file convention.
- Preserve Swift 6 strict concurrency and zero-warning expectations.

## Tests

For a bug fix:
1. Add or identify a regression test that fails for the original behavior.
2. Implement the fix.
3. Run the narrowest relevant test first.
4. Run broader verification appropriate to the changed boundary.

Normal development test entry point:

```zsh
scripts/run-development-tests.sh
```

Targeted example:

```zsh
scripts/run-development-tests.sh ClipboardHistoryTests/PasteStackTests
```

Static quality:

```zsh
scripts/verify-static-quality.sh
```

Do not claim UI, CoreAudio, IOKit/HID, Accessibility, signing, or final Community artifact behavior was verified unless it was actually exercised on a compatible macOS environment.

## High-risk changes

Changes to deletion, Clear History, encryption, key rotation, migrations, archive parsing, recovery, pasteboard identity, or persistent sensitive metadata require:
- negative-path tests,
- failure-injection coverage where practical,
- verification of both in-memory and persisted state,
- explicit review against `docs/ENGINEERING_INVARIANTS.md`.

## Performance

- Measure before adding complexity.
- Reuse the existing demand-based System Monitor sampling model.
- A metric requested by multiple views must still be sampled once per interval.
- Stop or reduce work when there are no consumers.
- Avoid wakeups that exist only to repaint unchanged UI.
- Treat timer count, sampling frequency, CPU wakeups, and battery impact as review items.

## Documentation

Update documentation when behavior, privacy guarantees, release requirements, architecture, or known limitations change.

Do not rewrite historical release evidence to make a new change look previously verified.

## Completion

Before reporting completion:
- inspect the final diff,
- list tests/checks actually run,
- state any macOS-only validation that remains,
- call out any new risk or follow-up separately from completed work.
