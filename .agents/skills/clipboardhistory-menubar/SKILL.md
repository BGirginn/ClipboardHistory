---
name: clipboardhistory-menubar
description: Design, implement, or review ClipboardHistory Control Center and menu-bar behavior, NSStatusItem lifecycle, independent feature pinning, combined system metrics, topbar customization, popover anchoring, notch/space behavior, and future external menu-bar management. Trigger for AppKit menu-bar or Control Center placement changes.
---

# Menu Bar and Control Center Workflow

Read:
- shell/menu-bar configuration code,
- `FeatureRegistry`,
- `MenuBarConfiguration`,
- `MenuBarConfigurationStore`,
- `MenuBarController`,
- relevant Control Center views/models,
- System Monitor menu-bar views when metrics are involved.

## Existing product model

Support these independently:
- Control Center icon,
- feature visible in Control Center,
- feature pinned independently to the menu bar,
- hybrid use.

Do not force a feature into only one placement if the existing model supports both.

## NSStatusItem lifecycle

- All status-item creation/removal/update must occur on MainActor.
- Prefer a diff:
  desired IDs vs existing IDs.
- Preserve existing `NSStatusItem` instances when only title/icon/value/config changes.
- Fully detach handlers/popovers/observers when an item is actually removed.
- Do not rebuild the entire status bar on every metric tick.

## Metrics

Numeric compact presentation is the primary top-bar model.
Multiple metrics may share one sampled state even when rendered as separate status items.
Combined vs separate metric items is a presentation decision, not a sampling decision.

## Space/notch

Do not promise that arbitrary menu-bar space is available.
Design overflow mitigation:
- compact formatting,
- combined metrics,
- user-controlled ordering/visibility,
- Control Center as a fallback access surface.

## External menu-bar manager

Treat management of other apps' or macOS system items as a separate subsystem from this app's own status items.

Do not assume a public API exists to literally reparent arbitrary external status items into the ClipboardHistory popover.

For each external item capability classify support:
- discoverable,
- hideable,
- movable,
- proxy-clickable,
- observable,
- unsupported/fragile.

Require graceful degradation across macOS versions and avoid making core ClipboardHistory features depend on private/fragile behavior.

## Testing

Cover:
- rapid toggle on/off,
- combined + separate combinations,
- shared state consistency,
- status item identity where important,
- popover open/close,
- multi-display/notch behavior manually where automation cannot prove it,
- no duplicate producers when multiple UI surfaces are active.
