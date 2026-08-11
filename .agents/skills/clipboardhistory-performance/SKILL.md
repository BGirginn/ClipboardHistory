---
name: clipboardhistory-performance
description: Analyze or optimize ClipboardHistory CPU usage, battery impact, polling, timers, async loops, System Monitor sampling, sensor reads, redraw frequency, background module lifecycle, and resource ownership. Trigger for performance, wakeup, live metrics, battery, idle-work, or sampling changes.
---

# Performance and Battery Workflow

Read:
- `docs/PERFORMANCE.md`
- System Monitor controller/provider code,
- the feature lifecycle that owns the work,
- existing benchmark/performance tests.

## First principle

Do not optimize by intuition alone. Identify:
- producer,
- consumers,
- cadence,
- cost per sample,
- update/render frequency,
- idle state,
- duplication.

## System Monitor

Preserve the existing demand-oriented centralized sampling model.

One sample should fan out to multiple consumers:

```text
active consumers
      |
      v
required cadence
      |
      v
single provider sample
      |
      v
shared sampled state
      |
      +-- menu bar
      +-- control center
      `-- detail UI
```

Do not create a timer per metric widget or per view.

When adding a consumer, express demand to the coordinator rather than directly polling the provider.

## Background lifecycle

Classify continuous work as:
- required while always enabled,
- required only while a menu-bar value is visible,
- required only while a popover/detail view is open,
- safe to run at reduced cadence,
- safe to suspend entirely.

If there are zero consumers, stop or reduce work unless another explicit feature requirement exists.

## UI updates

Separate sampling cadence from rendering cadence when needed.
Avoid repainting unchanged text/state.
Prefer stable menu-bar object identity and value updates.
Use monospaced digits for numeric menu-bar metrics where width jitter matters.

## Battery adaptation

Battery-aware cadence changes are allowed only when they do not violate a user-visible freshness contract. Keep the policy centralized and configurable rather than scattering `ProcessInfo`/power checks across providers.

## Native sensors

C/Objective-C/IOKit/HID is not automatically "faster" merely because of language choice. Measure the native call cost and synchronization/wakeup behavior.

## Verification

Use repository benchmarks/performance scripts when the change can affect hot paths:

```zsh
scripts/verify-performance.sh
```

Also run relevant correctness tests and static quality.

State clearly when Instruments/Energy Log or real Apple-silicon sensor measurements remain necessary.
