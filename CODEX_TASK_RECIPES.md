# Codex Task Recipes

Use these as starting prompts for a new Codex thread. Replace bracketed fields with the actual task.

## Feature implementation

```text
Implement [FEATURE/CHANGE] in ClipboardHistory.

Before editing:
1. Read AGENTS.md.
2. Inspect git status.
3. Read the affected feature, shared services, tests, docs/ARCHITECTURE.md, and relevant invariants.
4. Identify existing abstractions before adding new ones.

Constraints:
- Preserve shared-controller/single-producer architecture.
- Do not create duplicate timers, polling loops, or data sources.
- Do not weaken privacy, encryption, deletion, Keychain, or migration behavior.
- Keep AppKit UI mutations on MainActor.
- Add regression/behavior tests for the new path.
- Run the narrowest relevant tests, then static quality.
- Review the final diff.

Deliver:
- implementation,
- tests,
- exact checks run,
- remaining macOS/manual validation,
- risks or follow-ups.
```

## Bug fix

```text
Fix this bug in ClipboardHistory: [BUG].

Do not patch only the visible symptom.

Workflow:
1. Reproduce or prove the failing invariant from code/tests.
2. Identify the root cause and every persistent/UI state affected.
3. Add a regression test that fails before the fix where practical.
4. Make the smallest root-cause fix.
5. Test success, failure, and cancellation/rollback paths where relevant.
6. Run static quality and the relevant targeted test suite.
7. Inspect the final diff for unrelated edits.

If this touches storage, encryption, deletion, migration, archive import/export, sensitive content, pasteboard identity, CoreAudio, or system APIs, use the matching project skill.
```

## Architecture review without implementation

```text
Review [AREA/PROPOSAL] in ClipboardHistory. Do not write code.

First read the existing implementation rather than designing from filenames.

Return:
1. Current implementation and data flow.
2. What is already correct and should be preserved.
3. Gaps or constraints.
4. Proposed target architecture.
5. Alternatives considered.
6. Privacy/security effects.
7. CPU/battery effects.
8. Migration/backward-compatibility effects.
9. Testing requirements.
10. Ordered implementation phases.

Clearly mark facts from the repository versus recommendations/inferences.
```

## Privacy and storage review

```text
Perform an adversarial privacy/data-integrity review of [CHANGE/FILES].

Use docs/ENGINEERING_INVARIANTS.md and the clipboardhistory-privacy-storage skill.

Trace:
UI state -> controller -> storage call -> SQLite/assets/backups -> encryption/key state -> restart/recovery.

Look specifically for:
- fail-open deletion,
- UI state committed before persistence,
- stranded ciphertext,
- plaintext metadata,
- orphan assets/temp files,
- incomplete rollback,
- stale rich payloads,
- misleading privacy guarantees.

Do not accept a passing happy-path unit test as sufficient evidence.
```

## Performance and battery review

```text
Review [FEATURE] for macOS CPU/battery impact.

Use the clipboardhistory-performance skill.

Inventory:
- timers,
- polling loops,
- AsyncStream/Task loops,
- native API samples,
- repaint/update frequency,
- active consumers,
- idle behavior,
- wakeup amplification,
- duplicate producers.

Prefer extending the existing centralized demand-based sampling/lifecycle model.

Return measured or measurable concerns, not generic optimization advice.
```

## Release readiness

```text
Assess the current commit for release readiness.

Use the clipboardhistory-release skill.

Do not infer successful verification from scripts existing in the repo.
Separate:
- checks actually run now,
- historical evidence,
- checks that require signed/interactively logged-in macOS,
- remaining manual/device/browser acceptance.

Report blockers first.
```
