# External drawer feasibility probes

These experiments are separate from CoreDeck's production targets. `Probe.swift`
is read-only. The activation and movement programs below post real input and
require an isolated test session with Accessibility permission already granted.

```sh
xcrun swiftc -parse-as-library Experiments/DrawerFeasibility/Probe.swift \
  -o /private/tmp/coredeck-drawer-feasibility-probe
/private/tmp/coredeck-drawer-feasibility-probe
```

The probe lists the five required system-item AX roles, identifiers, current
geometry, native actions, and whether Accessibility reports `AXPosition` as
settable. Geometry is transient evidence and is never treated as identity. The
probe still performs no action and changes no system state. On macOS 27.0 beta,
`ControlCenter` and `SystemUIServer` returned `-25212` for `AXExtrasMenuBar`,
while `MenuBarAgent` exposed all five required identifiers. The first probe
missed Wi-Fi because its visible label did not contain the literal `Wi-Fi`;
matching the AX identifier found it. This does not establish identity stability,
moving, activation, or restore on supported macOS 14.2+/15/26.

M2 requires a separate interactive test host and raw evidence for each required
item and OS: stable identity, move that actually frees menu-bar space, native
activation, restore, permission withdrawal, restart/crash recovery, duplicate
icons from one application, and another manager's interference. A missing or
unsafe capability blocks the full drawer candidate.

The recorded Command-drag swaps only demonstrate reordering. They do not hide
an item or reclaim occupied menu-bar space, so they do not satisfy M2's space
requirement. The activation probe observes a new system window; it does not
yet validate the identity of the opened panel. Permission withdrawal, conflicting
managers, interrupted journal writes, and native recovery after arbitrary crashes
also remain unverified. Synthetic journal checks do not close those gates.
Do not use these experiments as a production adapter
or automatically retry a failed recovery.

`ActivationProbe.swift` is the first interactive step. It accepts only the five
required stable identifiers (or `all`), calls the advertised `AXShowMenu`
action, verifies that a visible native menu appeared, and immediately sends
Escape. It does not move items or change persistent settings:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swiftc -warnings-as-errors -parse-as-library \
  Experiments/DrawerFeasibility/ActivationProbe.swift \
  -o /private/tmp/coredeck-drawer-activation-probe
/private/tmp/coredeck-drawer-activation-probe all
```

The action may return `kAXErrorCannotComplete` while the menu is doing modal
work. The probe accepts that status only when a new on-screen system window was
observed and then disappeared after Escape; the error code alone never counts
as success.

`MovementProbe.swift` performs one explicit Command-drag swap and immediate
restore. It writes the original stable-identifier order before posting input,
then records the moved and restored snapshots atomically. Clock and Control
Center and other identities outside the five required items are never selected
as swap neighbors. A missing restore verification is
a hard failure and leaves the journal for manual recovery inspection:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swiftc -warnings-as-errors -parse-as-library \
  Experiments/DrawerFeasibility/MovementProbe.swift \
  Experiments/DrawerFeasibility/MovementJournal.swift \
  Experiments/DrawerFeasibility/MovementJournalLock.swift \
  -o /private/tmp/coredeck-drawer-movement-probe
/private/tmp/coredeck-drawer-movement-probe \
  com.apple.menuextra.wifi /private/tmp/coredeck-drawer-movement.json \
  --confirm-system-menu-change
```

Restart recovery is tested explicitly by appending
`--leave-moved-for-restart`, restarting `MenuBarAgent`, and then running:

```sh
/private/tmp/coredeck-drawer-movement-probe \
  --recover /path/to/the-journal.json --confirm-system-menu-change
```

The leave-moved option is successful only when the journal reaches `moved`;
the recovery command must later reach `restored` with the original stable-ID
order and target position.

The probe now refuses to overwrite an existing journal. A per-user process lock
serializes cooperating movement/recovery probes, even when they use different
journal paths. The lock is released by the OS after a crash; its file remains
intentionally present. It does not lock out other menu managers.
Journal loading rejects symlinks, non-regular files, empty files and files over
1 MiB before decoding. Corrupt JSON never reaches an input operation.

Recovery validates the journal version, OS, unique stable identities, adjacent
original pair, full item order and geometry before posting input. A `prepared`
journal can recover a crash between dragging and recording `moved` only when
the complete observed layout equals the intended swap. Missing/duplicate items,
an unrelated rearrangement, a changed display layout or a completed journal with
later movement stops without dragging. Recovery requires an explicit command;
there is no automatic retry. All drag events, including mouse-up, are allocated
before mouse-down, and permission is checked during dragging. Permission loss
still requires real-device testing because the OS may reject the release event.

The synthetic regression suite exercises these decisions and lock contention
without Accessibility or input events, then compiles the interactive probe:

```sh
zsh Tests/Scripts/test_drawer_movement_journal.sh
```

`DuplicateStatusItemHost.swift` creates two same-title AppKit status items from
one process. `DuplicateIdentityProbe.swift` requires both distinct accessibility
identifiers to be present exactly once. The host exits automatically after 20
seconds so the fixture cannot remain in the user's menu bar.
