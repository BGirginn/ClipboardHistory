# Engineering Invariants

These are product-level invariants. A change that violates one is incorrect even if it compiles and its happy-path tests pass.

## 1. Persistent deletion must be truthful

If the UI reports that clipboard history was deleted, the corresponding persistent data targeted by that action must actually be removed or the action must report failure.

Deletion logic must account for all relevant persistence locations:
- SQLite rows,
- file assets,
- legacy/migration backups when they are part of the user's "clear all history" expectation,
- derived metadata that can reconstruct sensitive content.

Do not remove an item from in-memory state first and then permanently hide a failed persistent deletion.

## 2. Key rotation must not strand ciphertext

Never rotate or replace an encryption key while persistent records that still require the old key remain unreadable without a migration/re-encryption plan.

Collections, item metadata, assets, notes, and any other independently encrypted domains must be audited separately.

## 3. Security settings commit after successful migration

A setting such as "encrypt all items" must not be presented as successfully applied before required historical migration completes.

Valid patterns:
- transactional migration then setting commit,
- staged migration with explicit "migration in progress/failed" state,
- rollback to the prior setting on failure.

Logging an error while leaving the UI in a stronger security mode than reality is not acceptable.

## 4. Sensitive-content hiding must cover every presentation path

When sensitive content is intentionally concealed, verify:
- list previews,
- detail previews,
- edit fields,
- metadata,
- OCR text,
- QR results,
- Quick Look,
- drag/drop,
- copy/paste actions,
- accessibility labels where applicable.

A hidden preview is not sufficient if an adjacent editor exposes the same plaintext.

## 5. Privacy claims must match what macOS APIs can prove

Do not state "never read" or "never stored" if source attribution is inferred from the frontmost application after a polling delay rather than cryptographically or API-authoritatively tied to the copy event.

When the platform cannot guarantee a property:
- narrow the wording,
- document the limitation,
- fail safely where possible.

## 6. Secret detection is defense in depth

Secret-pattern matching can reduce accidental persistence but cannot be the only protection boundary.

Tests must include common private-key envelopes and credential shapes, including formats that differ only by header family.

## 7. "Encrypted item" requires an explicit metadata policy

If content is encrypted but sensitive metadata such as file URLs, bookmarks, paths, source identity, or extracted text remains plaintext, the product and UI must not imply full-record encryption.

Either:
- encrypt the metadata,
- intentionally classify it as non-secret and document why,
- or describe the feature as content encryption rather than whole-item encryption.

## 8. Storage quota cleanup must use reclaimable cost

Eviction decisions must be based on bytes that can actually be reclaimed from each candidate, not only asset size when database/text storage contributes materially to quota usage.

Pinned/protected items must not be evicted by a generic quota path unless the product contract explicitly permits it.

## 9. Edited rich content must not paste stale payload

When the user edits a rich-text item's visible text:
- update the corresponding rich payload,
- generate a new payload,
- or invalidate original rich representations.

A later "paste original" must not silently resurrect pre-edit content.

## 10. Temporary plaintext must have a lifecycle

If encrypted content is materialized as plaintext for Quick Look/export/paste:
- use a bounded temporary location,
- use restrictive permissions,
- remove it on normal close,
- provide startup cleanup for orphaned files after crash/kill when feasible,
- never leave predictable long-lived plaintext copies.

## 11. Import/migration is a transaction boundary

Import and migration logic must consider database and filesystem state together.

On failure:
- do not leave orphan assets,
- do not advance migration markers incorrectly,
- preserve a recoverable source when destruction would be irreversible,
- surface rollback failure.

## 12. One metric sample can serve many consumers

CPU/RAM/network/disk/temperature providers must not be polled separately for every menu-bar or Control Center consumer.

The sampling coordinator determines the required cadence from active consumers. UI surfaces consume shared sampled state.

## 13. No-consumer work should stop or degrade

A module or provider that has no active consumer should not continue high-frequency work without a separate product requirement.

Possible states:
- active/high cadence,
- active/low cadence,
- suspended,
- event-only.

Battery mode can further lower non-critical cadence when user-facing freshness permits.

## 14. Menu-bar object identity should be stable

Prefer diffing/updating existing `NSStatusItem` objects over destroying/recreating the entire menu-bar graph for cosmetic/configuration changes.

All AppKit status-item lifecycle mutations belong on the main actor.

## 15. OS ABI boundaries require exact storage types

For CoreAudio, IOKit, HID, CoreFoundation, C, and Objective-C bridges:
- allocate the exact representation expected by the API,
- avoid writing raw bytes directly into an `Optional<T>` representation when the API expects `T`,
- verify byte counts,
- test real adapters separately from protocol stubs.

## 16. Test doubles do not validate native adapters

A passing controller test that injects a stub does not prove:
- CoreAudio property access,
- Accessibility event delivery,
- IOKit/HID behavior,
- status-item placement,
- signing/Keychain behavior,
- browser native messaging installation,
- real paste behavior.

Track these as explicit platform acceptance requirements.

## 17. Release evidence is immutable history

Release notes/readiness reports must describe evidence that actually existed for that release/commit.

New verification can be added as new evidence; historical documents should not be rewritten to imply earlier validation that did not happen.
