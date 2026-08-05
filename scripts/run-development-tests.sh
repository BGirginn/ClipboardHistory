#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
development_root="$repository_root/.build/DevelopmentTests"
derived_data="$development_root/DerivedData"
result_bundle="$development_root/Latest.xcresult"
maximum_cache_kib=$(( 2 * 1024 * 1024 ))

enforce_cache_limit() {
  [[ -d "$development_root" ]] || return 0
  local current_cache_kib
  current_cache_kib=$(du -sk "$development_root" | awk '{print $1}')
  if (( current_cache_kib > maximum_cache_kib )); then
    print "development tests: cache exceeded 2 GiB; resetting"
    rm -rf -- "$development_root"
    rmdir "$repository_root/.build" 2>/dev/null || true
  fi
}

if [[ ${1:-} == "--clean" ]]; then
  if (( $# != 1 )); then
    print -u2 "usage: $0 [test-selector | --clean]"
    exit 64
  fi
  rm -rf -- "$development_root"
  rmdir "$repository_root/.build" 2>/dev/null || true
  print "development tests: cache removed"
  exit 0
fi

if (( $# > 1 )); then
  print -u2 "usage: $0 [test-selector | --clean]"
  exit 64
fi

selector=${1:-ClipboardHistoryTests}
enforce_cache_limit
trap enforce_cache_limit EXIT

mkdir -p "$development_root"
rm -rf -- "$result_bundle"

cd "$repository_root"
xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO \
  "-only-testing:$selector" test

summary=$(xcrun xcresulttool get test-results summary --path "$result_bundle")
result=$(jq -r '.result' <<<"$summary")
passed_tests=$(jq -r '.passedTests' <<<"$summary")
[[ "$result" == "Passed" ]]
print "development tests: selector=$selector passed=$passed_tests cache=$development_root"
