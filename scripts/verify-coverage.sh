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
target_name=$(jq -r '.targets[] | select(.name == "ClipboardHistoryTestHost.app") | .name' "$report")
if [[ "$target_name" != "ClipboardHistoryTestHost.app" ]]; then
  print -u2 "coverage gate: ClipboardHistoryTestHost.app target is missing"
  exit 1
fi

failed=0
typeset -A reviewed_nonexecutable_sources
manifest="$repository_root/scripts/coverage-nonexecutable-sources.tsv"
if [[ ! -f "$manifest" ]]; then
  print -u2 "coverage gate: audited nonexecutable-source manifest is missing"
  exit 1
fi
while IFS=$'\t' read -r expected_hash source classification; do
  [[ "$expected_hash" == \#* || -z "$expected_hash" ]] && continue
  if [[ ! "$expected_hash" =~ '^[0-9a-f]{64}$' ||
        "$source" != ClipboardHistory/* || "$source" != *.swift ||
        "$source" == *..* || -z "$classification" ||
        -n "${reviewed_nonexecutable_sources[$source]-}" ||
        ! -f "$repository_root/$source" ]]; then
    print -u2 "coverage gate: invalid or duplicate audited source: $source"
    failed=1
    continue
  fi
  actual_hash=$(shasum -a 256 "$repository_root/$source" | cut -d ' ' -f 1)
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    print -u2 "coverage gate: audited source changed and needs review: $source"
    failed=1
    continue
  fi
  reviewed_nonexecutable_sources[$source]="$classification"
done < "$manifest"

while IFS= read -r source; do
  absolute="$repository_root/$source"
  values=$(jq -r --arg path "$absolute" '
    [.targets[] | select(.name == "ClipboardHistoryTestHost.app") | .files[] | select(.path == $path)]
    | if length == 1 then "\(.[0].lineCoverage)\t\(.[0].coveredLines)\t\(.[0].executableLines)" else "missing" end
  ' "$report")
  if [[ "$values" == "missing" ]]; then
    if [[ -n "${reviewed_nonexecutable_sources[$source]-}" ]]; then
      print "coverage exemption: $source (${reviewed_nonexecutable_sources[$source]})"
    else
      print -u2 "coverage gate: production source is missing from the report: $source"
      failed=1
    fi
    continue
  fi
  executable=${values##*$'\t'}
  if (( executable == 0 )); then
    if [[ -n "${reviewed_nonexecutable_sources[$source]-}" ]]; then
      print "coverage exemption: $source has no executable regions"
    else
      print -u2 "coverage gate: production source has no executable regions in the report: $source"
      failed=1
    fi
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

target_coverage=$(jq -r '.targets[] | select(.name == "ClipboardHistoryTestHost.app") | .lineCoverage' "$report")
if ! jq -en \
  --argjson coverage "$target_coverage" \
  --argjson minimum "$minimum_aggregate_coverage" \
  '$coverage >= $minimum' >/dev/null; then
  print -u2 "coverage gate: aggregate production coverage $target_coverage is below $minimum_aggregate_coverage"
  failed=1
fi

(( failed == 0 )) || exit 1
print "coverage gate: aggregate production coverage $target_coverage meets $minimum_aggregate_coverage; every executable production Swift source has executed coverage"
