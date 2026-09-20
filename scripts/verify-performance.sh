#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
evidence_parent=${COREDECK_EVIDENCE_ROOT:-/private/tmp/coredeck-release-evidence}
mkdir -p "$evidence_parent"
evidence=$(mktemp -d "$evidence_parent/performance.XXXXXX")
build_root=$(mktemp -d /private/tmp/coredeck-performance-work.XXXXXX)
trap 'rm -rf -- "$build_root" "$evidence/attachments"' EXIT
log="$evidence/performance.log"
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence/Environment.json" performance
print "performance gate: evidence=$evidence"

build_passed=1
if ! xcodebuild -quiet \
    -project "$repository_root/ClipboardHistory.xcodeproj" \
    -scheme ClipboardHistoryTests \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$build_root/DerivedData" \
    -resultBundlePath "$evidence/Performance.xcresult" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
    -only-testing:ClipboardHistoryTests/PerformanceBenchmarkTests test >"$log" 2>&1; then
  build_passed=0
fi

metrics="$evidence/performance-metrics.ndjson"
: > "$metrics"
if [[ -d "$evidence/Performance.xcresult" ]] && \
    xcrun xcresulttool export attachments \
      --path "$evidence/Performance.xcresult" \
      --output-path "$evidence/attachments" >"$evidence/attachment-export.log" 2>&1; then
  while IFS= read -r attachment; do
    jq -c 'select(type == "object" and .itemCount == 5000)' "$attachment" >> "$metrics"
  done < <(rg --files "$evidence/attachments" -g '*.json')
fi

if (( build_passed == 0 )); then
  sed -n '1,240p' "$log" >&2
  print -u2 "performance gate: benchmark failed; evidence=$evidence"
  exit 1
fi
if rg -n '(^|[[:space:]])(warning|error):' "$log"; then
  print -u2 "performance gate: build or linker diagnostic emitted"
  exit 1
fi
result=$(xcrun xcresulttool get test-results summary --path "$evidence/Performance.xcresult" | jq -r '.result')
[[ "$result" == "Passed" ]] || {
  print -u2 "performance gate: optimized benchmark did not pass"
  exit 1
}
[[ -s "$metrics" ]] || {
  print -u2 "performance gate: benchmark metrics are missing; evidence=$evidence"
  exit 1
}
if ! jq -esf "$repository_root/scripts/verify-performance-metrics.jq" \
    "$metrics" >/dev/null; then
  print -u2 "performance gate: measurement count, format, or p95 budget failed; evidence=$evidence"
  exit 1
fi
cat "$metrics"
print "performance gate: optimized arm64 p95 benchmark passed"
