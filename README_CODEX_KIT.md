# ClipboardHistory Codex Kit

Copy the contents of this kit into the repository root.

## Included

```text
AGENTS.md
.agents/
  skills/
    clipboardhistory-change-safety/
    clipboardhistory-privacy-storage/
    clipboardhistory-performance/
    clipboardhistory-menubar/
    clipboardhistory-audio-mixer/
    clipboardhistory-release/
docs/
  AI_PROJECT_CONTEXT.md
  AI_AUDIT_BASELINE.md
  ENGINEERING_INVARIANTS.md
  CODEX_TASK_RECIPES.md
```

## What each layer does

### `AGENTS.md`

Short rules that should apply to every Codex task in this repository:
- inspect before editing,
- preserve architecture,
- run appropriate tests,
- protect privacy/data integrity,
- avoid duplicate polling,
- report unverified macOS behavior honestly.

Keep this file relatively small. Put detailed workflows in skills.

### `.agents/skills/*`

Reusable expert workflows.

Use explicitly in Codex with the skill picker/mention when needed, or allow Codex to match them from their descriptions.

- `clipboardhistory-change-safety`: general implementation/refactor/bug-fix workflow
- `clipboardhistory-privacy-storage`: SQLite/assets/encryption/Keychain/deletion/migration/import/export
- `clipboardhistory-performance`: System Monitor, polling, CPU, battery, timers
- `clipboardhistory-menubar`: Control Center, NSStatusItem, topbar customization, future external manager
- `clipboardhistory-audio-mixer`: CoreAudio and browser audio bridge
- `clipboardhistory-release`: CI, test matrix, signing, artifacts, release evidence

### `docs/ENGINEERING_INVARIANTS.md`

The most important file after `AGENTS.md`.

These are correctness conditions such as:
- deletion must be persistent and truthful,
- key rotation must not strand ciphertext,
- security settings cannot claim success before migration succeeds,
- one metric sample must serve multiple consumers,
- native C APIs must receive exact storage types.

### `docs/AI_PROJECT_CONTEXT.md`

A short architecture map so a new Codex thread can orient itself without inventing a different architecture.

It does not replace reading current source.

### `docs/AI_AUDIT_BASELINE.md`

Records high-priority audit areas from commit `3c2a2f5`.

It deliberately tells future agents to verify each finding against current code before assuming it is still unresolved.

### `docs/CODEX_TASK_RECIPES.md`

Ready-to-paste prompts for:
- feature implementation,
- bug fixing,
- architecture review,
- privacy/storage review,
- performance review,
- release readiness.

## Recommended usage

For a normal task:

```text
Read AGENTS.md, then implement [task]. Use the relevant ClipboardHistory skill.
```

For a storage/privacy task:

```text
Use $clipboardhistory-privacy-storage.
Fix [issue]. Prove the persistent-state invariant before editing and add a regression test.
```

For System Monitor:

```text
Use $clipboardhistory-performance.
Review/implement [change] without creating duplicate producers or per-widget timers.
```

For menu-bar work:

```text
Use $clipboardhistory-menubar.
Implement [change] while preserving hybrid Control Center + independent status-item behavior.
```

For release:

```text
Use $clipboardhistory-release.
Assess this exact commit. Separate executed evidence from historical or unrun checks.
```
