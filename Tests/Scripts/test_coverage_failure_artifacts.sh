#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-coverage-failure-test.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
print -u2 'synthetic xcodebuild failure'
exit 65
SCRIPT
chmod +x "$temporary_root/bin/xcodebuild"

if PATH="$temporary_root/bin:$PATH" \
    "$repository_root/scripts/run-coverage-suite.sh" \
      "$temporary_root/evidence" > "$temporary_root/command.log" 2>&1; then
  print -u2 'coverage failure regression: failed build passed'
  exit 1
fi
rg -q 'synthetic xcodebuild failure' "$temporary_root/evidence/Unit.log"
rg -q 'coverage suite: unit run failed' "$temporary_root/command.log"
[[ -s "$temporary_root/evidence/Environment.json" ]]
print 'coverage failure regression: environment and failed-run log retained'

cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
while (( $# > 0 )); do
  if [[ "$1" == -resultBundlePath ]]; then
    mkdir -p "$2"
    print 'synthetic raw failure result' > "$2/fixture.txt"
    break
  fi
  shift
done
exit 65
SCRIPT
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
if [[ "${SYNTHETIC_SUMMARY_FAILURE:-0}" == 1 ]]; then
  print -u2 'synthetic unreadable result bundle'
  exit 1
fi
print '{"result":"Failed","passedTests":0,"failedTests":1}'
SCRIPT
chmod +x "$temporary_root/bin/xcrun"
for mode in readable unreadable; do
  export SYNTHETIC_SUMMARY_FAILURE=0
  [[ "$mode" != unreadable ]] || export SYNTHETIC_SUMMARY_FAILURE=1
  if PATH="$temporary_root/bin:$PATH" \
      "$repository_root/scripts/run-coverage-suite.sh" \
      "$temporary_root/$mode" > "$temporary_root/$mode.log" 2>&1; then
    print -u2 'coverage failure regression: failed result bundle passed'
    exit 1
  fi
  [[ -s "$temporary_root/$mode/Unit.xcresult/fixture.txt" ]]
  if [[ "$mode" == readable ]]; then
    jq -e '.result == "Failed" and .failedTests == 1' \
      "$temporary_root/$mode/UnitSummary.json" >/dev/null
  else
    [[ ! -e "$temporary_root/$mode/UnitSummary.json" ]]
    rg -q 'synthetic unreadable result bundle' "$temporary_root/$mode/UnitSummaryExport.log"
  fi
done
print 'coverage failure regression: failed summaries and unreadable-result diagnostics retained'

python3 - "$repository_root" "$temporary_root/unit-inventory.json" <<'PY'
import json
import re
import sys
from pathlib import Path
names = []
for source in (Path(sys.argv[1]) / "Tests/Unit").glob("*.swift"):
    names.extend(re.findall(r"\bfunc\s+(test\w+)\s*\(", source.read_text()))
Path(sys.argv[2]).write_text(json.dumps({"testNodes": [
    {"nodeType": "Test Case", "name": name + "()", "result": "Passed"}
    for name in names
]}))
PY
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
while (( $# > 0 )); do
  if [[ "$1" == -resultBundlePath ]]; then
    mkdir -p "$2"
    print 'synthetic raw result' > "$2/fixture.txt"
    [[ "$2" != */Unit.xcresult ]] || exit 0
    print -u2 'synthetic UI authentication canceled'
    exit 65
  fi
  shift
done
exit 1
SCRIPT
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
if [[ "$4" == tests ]]; then
  cat "${0:A:h:h}/unit-inventory.json"
elif [[ "$@" == *'/Unit.xcresult'* ]]; then
  print '{"result":"Passed","failedTests":0}'
else
  print '{"result":"Failed","failedTests":1}'
fi
SCRIPT
if PATH="$temporary_root/bin:$PATH" \
    "$repository_root/scripts/run-coverage-suite.sh" \
    "$temporary_root/ui-failure" > "$temporary_root/ui-failure.log" 2>&1; then
  print -u2 'coverage failure regression: failed UI initialization passed'
  exit 1
fi
jq -e '.result == "Passed"' "$temporary_root/ui-failure/UnitSummary.json" >/dev/null
jq -e '.result == "Failed"' "$temporary_root/ui-failure/UISummary.json" >/dev/null
rg -q 'synthetic UI authentication canceled' "$temporary_root/ui-failure/UI.log"
[[ -s "$temporary_root/ui-failure/Unit.xcresult/fixture.txt" ]]
[[ -s "$temporary_root/ui-failure/UI.xcresult/fixture.txt" ]]
[[ ! -e "$temporary_root/ui-failure/Combined.xccovreport" ]]
print 'coverage failure regression: UI initialization failure preserves both summaries and raw results'
