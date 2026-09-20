#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-mutation-failure.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
print -u2 'synthetic mutation test failure'
exit 65
SCRIPT
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
if [[ "$MUTATION_SCENARIO" == crash ]]; then
  print '{"result":"Failed","failedTests":1,"skippedTests":0,"testFailures":[{"failureText":"Test runner crashed","testIdentifierString":"ClipboardMonitorTests/testIdentity()"}]}'
else
  print '{}'
fi
SCRIPT
chmod +x "$temporary_root/bin/xcodebuild" "$temporary_root/bin/xcrun"
for scenario in build crash; do
  if PATH="$temporary_root/bin:$PATH" MUTATION_SCENARIO="$scenario" \
      COREDECK_EVIDENCE_ROOT="$temporary_root/$scenario" \
      "$repository_root/scripts/run-critical-mutations.sh" > "$temporary_root/$scenario.log" 2>&1; then
    print -u2 "mutation regression: accepted $scenario failure"
    exit 1
  fi
  rg -q 'mutation infrastructure failure' "$temporary_root/$scenario.log"
  evidence=("$temporary_root/$scenario"/mutations.*)
  [[ ${#evidence} == 1 && -s "$evidence/Environment.json" ]]
  [[ -s "$evidence/pasteboard_identity/Mutation.patch" ]]
  [[ -s "$evidence/pasteboard_identity/Summary.json" ]]
  rg -q 'synthetic mutation test failure' "$evidence/pasteboard_identity/test.log"
  [[ ! -e "$evidence/pasteboard_identity/work" ]]
done
print 'mutation regression: build failure and crash are not killed mutations; evidence retained'
