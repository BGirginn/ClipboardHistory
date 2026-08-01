#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
temporary_root=$(mktemp -d /private/tmp/clipboardhistory-sanitizers.XXXXXX)
trap 'rm -rf "$temporary_root"' EXIT

run_sanitizer() {
  local name=$1
  local setting=$2
  local log="$temporary_root/$name.log"
  if ! xcodebuild -quiet \
      -project "$repository_root/ClipboardHistory.xcodeproj" \
      -scheme ClipboardHistory \
      -configuration Debug \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$temporary_root/$name" \
      -resultBundlePath "$temporary_root/$name.xcresult" \
      CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
      "$setting" YES \
      -only-testing:ClipboardHistoryTests \
      -skip-testing:ClipboardHistoryTests/PerformanceBenchmarkTests test >"$log" 2>&1; then
    sed -n '1,240p' "$log" >&2
    exit 1
  fi
  if rg -n '(^|[[:space:]])(warning|error):|ThreadSanitizer:|AddressSanitizer:' "$log"; then
    print -u2 "sanitizer gate: $name emitted a diagnostic"
    exit 1
  fi
  summary=$(xcrun xcresulttool get test-results summary --path "$temporary_root/$name.xcresult")
  [[ "$(jq -r '.result' <<<"$summary")" == "Passed" ]] || {
    print -u2 "sanitizer gate: $name tests did not pass"
    exit 1
  }
  print "sanitizer gate: $name passed $(jq -r '.passedTests' <<<"$summary") tests"
}

run_sanitizer asan -enableAddressSanitizer
run_sanitizer tsan -enableThreadSanitizer
