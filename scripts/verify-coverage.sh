#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ( ! -d "$1" && ! -f "$1" ) ]]; then
  print -u2 "usage: $0 /path/to/Test.xcresult-or-Combined.xccovreport"
  exit 64
fi

repository_root=${0:A:h:h}
result_bundle=${1:A}
report=$(mktemp /private/tmp/clipboardhistory-coverage.XXXXXX.json)
trap 'rm -f "$report"' EXIT

if [[ -d "$result_bundle" ]]; then
  xcrun xccov view --report --json "$result_bundle" > "$report"
else
  xcrun xccov view --json "$result_bundle" > "$report"
fi
target_name=$(jq -r '.targets[] | select(.name == "ClipboardHistory.app") | .name' "$report")
if [[ "$target_name" != "ClipboardHistory.app" ]]; then
  print -u2 "coverage gate: ClipboardHistory.app target is missing"
  exit 1
fi

failed=0
while IFS= read -r source; do
  absolute="$repository_root/$source"
  values=$(jq -r --arg path "$absolute" '
    [.targets[] | select(.name == "ClipboardHistory.app") | .files[] | select(.path == $path)]
    | if length == 1 then "\(.[0].lineCoverage)\t\(.[0].coveredLines)\t\(.[0].executableLines)" else "missing" end
  ' "$report")
  if [[ "$values" == "missing" ]]; then
    # xccov omits source files that contain no executable regions.
    continue
  fi
  coverage=${values%%$'\t'*}
  if [[ "$coverage" != "1" && "$coverage" != "1.0" ]]; then
    print -u2 "coverage gate: $source -> $values"
    failed=1
  fi
done < <(cd "$repository_root" && rg --files ClipboardHistory -g '*.swift' | sort)

target_coverage=$(jq -r '.targets[] | select(.name == "ClipboardHistory.app") | .lineCoverage' "$report")
if [[ "$target_coverage" != "1" && "$target_coverage" != "1.0" ]]; then
  print -u2 "coverage gate: aggregate production coverage is $target_coverage"
  failed=1
fi

(( failed == 0 )) || exit 1
print "coverage gate: every production Swift file is at 100% line coverage"
