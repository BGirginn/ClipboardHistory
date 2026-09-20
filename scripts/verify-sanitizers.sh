#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
evidence_parent=${COREDECK_EVIDENCE_ROOT:-/private/tmp/coredeck-release-evidence}
mkdir -p "$evidence_parent"
evidence=$(mktemp -d "$evidence_parent/sanitizers.XXXXXX")
build_root=$(mktemp -d /private/tmp/coredeck-sanitizers-work.XXXXXX)
trap 'rm -rf -- "$build_root"' EXIT
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence/Environment.json" sanitizers
print "sanitizer gate: evidence=$evidence"

run_sanitizer() {
  local name=$1
  local setting=$2
  local log="$evidence/$name.log"
  if ! xcodebuild -quiet \
      -project "$repository_root/ClipboardHistory.xcodeproj" \
      -scheme ClipboardHistoryTests \
      -configuration Debug \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$build_root/$name-derived" \
      -resultBundlePath "$evidence/$name.xcresult" \
      CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
      "$setting" YES \
      -only-testing:ClipboardHistoryTests \
      -skip-testing:ClipboardHistoryTests/PerformanceBenchmarkTests test >"$log" 2>&1; then
    sed -n '1,240p' "$log" >&2
    print -u2 "sanitizer gate: $name failed; evidence=$evidence"
    exit 1
  fi
  if rg -n '(^|[[:space:]])(warning|error):|ThreadSanitizer:|AddressSanitizer:' "$log"; then
    print -u2 "sanitizer gate: $name emitted a diagnostic"
    exit 1
  fi
  summary=$(xcrun xcresulttool get test-results summary --path "$evidence/$name.xcresult")
  [[ "$(jq -r '.result' <<<"$summary")" == "Passed" ]] || {
    print -u2 "sanitizer gate: $name tests did not pass"
    exit 1
  }
  print "sanitizer gate: $name passed $(jq -r '.passedTests' <<<"$summary") tests"
}

run_sanitizer asan -enableAddressSanitizer
run_sanitizer tsan -enableThreadSanitizer
