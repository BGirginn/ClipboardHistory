#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-test-summary.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin" "$temporary_root/scripts"
cp "$repository_root/scripts/run-development-tests.sh" "$temporary_root/scripts/"
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
exit 0
SCRIPT
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
cat "$TEST_SUMMARY_PATH"
SCRIPT
chmod +x "$temporary_root/bin/xcodebuild" "$temporary_root/bin/xcrun"
export TEST_SUMMARY_PATH="$temporary_root/summary.json"
export PATH="$temporary_root/bin:$PATH"

for scenario in empty skipped failed incomplete missing passed; do
  case "$scenario" in
    empty) counts='0,0,0,0' ;;
    skipped) counts='1,0,1,2' ;;
    failed) counts='1,1,0,2' ;;
    incomplete) counts='1,0,0,2' ;;
    missing) counts='1,null,null,null' ;;
    passed) counts='1,0,0,1' ;;
  esac
  jq -n --argjson counts "[$counts]" '{
    result: "Passed", passedTests: $counts[0], failedTests: $counts[1],
    skippedTests: $counts[2], totalTestCount: $counts[3], expectedFailures: 0
  }' > "$TEST_SUMMARY_PATH"
  if "$temporary_root/scripts/run-development-tests.sh" ClipboardHistoryTests/SelectedCase \
      > "$temporary_root/$scenario.log" 2>&1; then
    [[ "$scenario" == passed ]] || {
      print -u2 "development test summary regression: accepted $scenario"
      exit 1
    }
  else
    [[ "$scenario" != passed ]] || {
      cat "$temporary_root/$scenario.log" >&2
      exit 1
    }
    rg -q 'selector produced no tests' "$temporary_root/$scenario.log"
  fi
done
print 'development test summary: zero, skipped, failed, incomplete and missing results rejected; complete result accepted'
