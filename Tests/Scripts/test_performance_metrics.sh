#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-performance-metrics-test.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
filter="$repository_root/scripts/verify-performance-metrics.jq"
print '{"itemCount":5000,"repetitions":100,"writeP95Ms":35,"readP95Ms":18,"modelLoadP95Ms":74,"filterP95Ms":9,"layoutP95Ms":18}' \
  > "$temporary_root/valid.json"
jq -esf "$filter" "$temporary_root/valid.json" >/dev/null

for defect in missing over_budget short_run; do
  case "$defect" in
    missing) jq 'del(.writeP95Ms)' "$temporary_root/valid.json" > "$temporary_root/$defect.json" ;;
    over_budget) jq '.readP95Ms = 51' "$temporary_root/valid.json" > "$temporary_root/$defect.json" ;;
    short_run) jq '.repetitions = 20' "$temporary_root/valid.json" > "$temporary_root/$defect.json" ;;
  esac
  if jq -esf "$filter" "$temporary_root/$defect.json" >/dev/null; then
    print -u2 "performance regression: $defect passed"
    exit 1
  fi
done
cat "$temporary_root/valid.json" "$temporary_root/valid.json" \
  > "$temporary_root/duplicate.json"
if jq -esf "$filter" "$temporary_root/duplicate.json" >/dev/null; then
  print -u2 'performance regression: duplicate metric attachment passed'
  exit 1
fi
print 'performance regression: missing, excessive, short, and duplicate metrics fail'
