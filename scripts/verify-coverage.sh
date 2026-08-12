#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ( ! -d "$1" && ! -f "$1" ) ]]; then
  print -u2 "usage: $0 /path/to/Test.xcresult-or-Combined.xccovreport"
  exit 64
fi

repository_root=${0:A:h:h}
result_bundle=${1:A}
minimum_aggregate_coverage=0.95
low_file_coverage_warning=0.80
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
  if ! jq -en --argjson coverage "$coverage" '$coverage > 0' >/dev/null; then
    print -u2 "coverage gate: production source has no executed lines: $source -> $values"
    failed=1
  elif ! jq -en \
    --argjson coverage "$coverage" \
    --argjson warning "$low_file_coverage_warning" \
    '$coverage >= $warning' >/dev/null; then
    print -u2 "coverage warning: $source -> $values"
  fi
done < <(cd "$repository_root" && rg --files ClipboardHistory -g '*.swift' | sort)

target_coverage=$(jq -r '.targets[] | select(.name == "ClipboardHistory.app") | .lineCoverage' "$report")
if ! jq -en \
  --argjson coverage "$target_coverage" \
  --argjson minimum "$minimum_aggregate_coverage" \
  '$coverage >= $minimum' >/dev/null; then
  print -u2 "coverage gate: aggregate production coverage $target_coverage is below $minimum_aggregate_coverage"
  failed=1
fi

(( failed == 0 )) || exit 1
print "coverage gate: aggregate production coverage $target_coverage meets $minimum_aggregate_coverage and every production Swift source has executed coverage"
