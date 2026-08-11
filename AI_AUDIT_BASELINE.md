# AI Audit Baseline

Baseline repository snapshot used for the comprehensive review:

```text
repository: BGirginn/ClipboardHistory
branch: main
commit: 3c2a2f583cd3deb0b5009cf33c76cc8ef9a5c13b
```

This document is a routing aid for coding agents. It must not be treated as proof that a finding is still present after later commits. Re-open the current code before fixing or citing any item.

## High-priority areas identified at the baseline

### Persistent deletion / Clear History

Review whether the Clear History flow:
- removes all intended history persistence,
- leaves encrypted collections dependent on a rotated/removed key,
- reports storage failure truthfully,
- accounts for legacy/migration backups.

### Encryption migration

Review whether the requested encryption mode is committed in UI/preferences before all historical content is successfully migrated.

### Sensitive detail presentation

Review whether sensitive content hidden in a preview can still appear in editable/detail fields, metadata, OCR/QR output, Quick Look, or another presentation path.

### Excluded application semantics

Review the difference between:
- the application that actually copied content,
- the frontmost application observed by a delayed pasteboard poll.

Do not promise "never read" unless the current implementation can actually establish the source strongly enough.

### Secret detection coverage

Review common private-key envelope variants, not only a single SSH/key family.

### Encrypted record metadata

Review file URL/bookmark/path and other metadata persistence when the user expects encryption.

### Storage quota

Review whether eviction accounting reflects actual reclaimable database + asset cost.

### Rich-text editing

Review whether editing visible text invalidates or regenerates stored RTF/HTML/original payloads.

### Temporary plaintext

Review Quick Look/export/paste temporary files for cleanup, crash orphaning, names/permissions and startup hygiene.

### Audio Mixer native adapter

Review CoreAudio generic scalar-property reads to ensure C APIs write into exact `Value` storage rather than an `Optional<Value>` representation.

## Baseline strengths to preserve

- actor-based storage coordination,
- SQLite WAL/FULLMUTEX strategy,
- authenticated encryption and Keychain-backed key material,
- distinct security domains such as history/note keys,
- modular feature architecture,
- shared feature state/controllers,
- demand-based centralized System Monitor sampling,
- strict-concurrency expectations,
- extensive unit/integration/static/sanitizer/performance/release scripts,
- archive validation and failure-injection direction.

## Rule for future agents

Before acting on a baseline finding:
1. Locate the current code.
2. Prove whether the issue still exists.
3. Locate existing regression tests.
4. Avoid reintroducing a fix already present under a different implementation.
