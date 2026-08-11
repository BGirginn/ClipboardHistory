---
name: clipboardhistory-privacy-storage
description: Review or change ClipboardHistory storage, SQLite, assets, deletion, Clear History, encryption, Keychain, sensitive-content handling, migrations, recovery, import/export, archives, Quick Look temp data, and persistent privacy guarantees. Trigger for any data-integrity or privacy-sensitive persistence change.
---

# Privacy and Storage Safety Workflow

Read:
- `docs/ENGINEERING_INVARIANTS.md`
- `docs/PRIVACY_AND_THREAT_MODEL.md`
- `docs/ARCHITECTURE.md`
- affected storage/security code and tests.

## Mandatory state model

Trace the operation across all applicable domains:

```text
UI/in-memory state
    |
controller
    |
StorageService / security service
    |
+-- SQLite
+-- assets
+-- backups
+-- temp files
+-- Keychain/key state
`-- migration/recovery markers
```

Never reason about only one layer.

## Review checklist

For writes/deletes:
- What happens if SQLite fails?
- What happens if filesystem mutation fails?
- Which state is committed first?
- Can restart resurrect content the UI claimed was removed?
- Can rollback itself fail, and is that surfaced?

For encryption:
- Which fields/assets/metadata are encrypted?
- Which key decrypts each domain?
- Can a key rotate while ciphertext using the old key survives?
- Does the UI commit "encrypted" before migration succeeds?
- Are plaintext temp files cleaned after crash?
- Is sensitive metadata still plaintext?

For Clear History:
- define exactly what "history" means,
- include DB rows, assets, relevant legacy backups, temporary derivatives, and dependent encrypted records,
- keep unrelated user data such as intentionally separate notes unless product semantics say otherwise.

For import/migration:
- validate input before destructive mutation,
- stage files where possible,
- prevent orphan assets,
- preserve recovery evidence,
- do not advance completion markers until the entire operation succeeds.

For sensitive content:
- inspect every display path, not only list previews,
- include editors, details, OCR/QR metadata, Quick Look and accessibility surfaces.

## Testing

Add tests for:
- primary success path,
- persistent failure,
- filesystem failure when injectable,
- rollback,
- restart/reload state,
- legacy/migration edge cases,
- negative/malicious archive input as relevant.

Run the narrow relevant tests, then static quality, then the full development suite if persistence semantics changed.

Do not weaken a privacy claim merely by changing tests. If the platform cannot enforce the claim, change product wording/documentation and behavior together.
