#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
temporary_root=$(mktemp -d /private/tmp/clipboardhistory-performance.XXXXXX)
trap 'rm -rf "$temporary_root"' EXIT
log="$temporary_root/performance.log"

if ! xcodebuild -quiet \
    -project "$repository_root/ClipboardHistory.xcodeproj" \
    -scheme ClipboardHistory \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$temporary_root/DerivedData" \
    -resultBundlePath "$temporary_root/Performance.xcresult" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
    -only-testing:ClipboardHistoryTests/PerformanceBenchmarkTests test >"$log" 2>&1; then
  sed -n '1,240p' "$log" >&2
  exit 1
fi
if rg -n '(^|[[:space:]])(warning|error):' "$log"; then
  print -u2 "performance gate: build or linker diagnostic emitted"
  exit 1
fi
result=$(xcrun xcresulttool get test-results summary --path "$temporary_root/Performance.xcresult" | jq -r '.result')
[[ "$result" == "Passed" ]] || {
  print -u2 "performance gate: optimized benchmark did not pass"
  exit 1
}
print "performance gate: optimized arm64 p95 benchmark passed"
