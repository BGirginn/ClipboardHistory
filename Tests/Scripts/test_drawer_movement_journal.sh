#!/bin/zsh
set -euo pipefail
repository_root=${0:A:h:h:h}
work_root=$(mktemp -d /private/tmp/coredeck-drawer-journal-test.XXXXXX)
trap 'rm -rf -- "$work_root"' EXIT
experiment="$repository_root/Experiments/DrawerFeasibility"
xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  "$experiment/MovementJournal.swift" "$experiment/MovementJournalLock.swift" \
  "$experiment/MovementJournalTests.swift" -o "$work_root/journal-tests"
"$work_root/journal-tests"
xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  "$experiment/MovementJournal.swift" "$experiment/MovementJournalLock.swift" \
  "$experiment/MovementProbe.swift" -o "$work_root/movement-probe"
print 'movement probe: Swift 6 build passed (interactive probe not run)'
