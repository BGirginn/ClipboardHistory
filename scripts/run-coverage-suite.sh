#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: $0 /path/to/new-coverage-evidence-directory"
  exit 64
fi

repository_root=${0:A:h:h}
evidence_root=${1:A}
if [[ -e "$evidence_root" ]]; then
  print -u2 "coverage suite: output already exists: $evidence_root"
  exit 1
fi
mkdir -p "$evidence_root"
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence_root/Environment.json" coverage

suite_succeeded=0
retain_raw_results=${CLIPBOARD_HISTORY_RETAIN_RAW_RESULTS:-0}
build_root=""
save_summary() {
  local kind=$1
  if ! xcrun xcresulttool get test-results summary \
      --path "$evidence_root/$kind.xcresult" \
      > "$evidence_root/${kind}Summary.json.partial" \
      2> "$evidence_root/${kind}SummaryExport.log"; then
    print -u2 "coverage suite: $kind summary export failed; raw evidence retained"
    return 1
  fi
  mv "$evidence_root/${kind}Summary.json.partial" "$evidence_root/${kind}Summary.json"
}
cleanup_transient_build_data() {
  local kind
  for kind in Unit UI; do
    if [[ -d "$evidence_root/$kind.xcresult" && ! -s "$evidence_root/${kind}Summary.json" ]]; then
      save_summary "$kind" || print -u2 "coverage suite: inspect ${kind}SummaryExport.log"
    fi
  done
  [[ -z "$build_root" ]] || rm -rf -- "$build_root"
  if (( suite_succeeded == 1 )); then
    rm -rf -- "$evidence_root/UnitCoverage" "$evidence_root/UICoverage"
  fi
  if (( suite_succeeded == 1 )) && [[ "$retain_raw_results" != 1 ]]; then
    rm -rf -- \
      "$evidence_root/Unit.xcresult" \
      "$evidence_root/UI.xcresult"
  fi
}
trap cleanup_transient_build_data EXIT
build_root=$(mktemp -d /private/tmp/coredeck-coverage-work.XXXXXX)

cd "$repository_root"
if ! xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistoryTests \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root/UnitDerivedData" \
  -resultBundlePath "$evidence_root/Unit.xcresult" \
  -enableCodeCoverage YES \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:ClipboardHistoryTests test >"$evidence_root/Unit.log" 2>&1; then
  cat "$evidence_root/Unit.log" >&2
  print -u2 "coverage suite: unit run failed; evidence=$evidence_root"
  exit 1
fi
save_summary Unit
python3 scripts/verify-test-inventory.py Unit "$evidence_root/Unit.xcresult"

# The production entitlement file is empty, so the isolated UI run can use an
# ad-hoc signature without an Apple account or provisioning profile.
if ! xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistoryTests \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root/UIDerivedData" \
  -resultBundlePath "$evidence_root/UI.xcresult" \
  -enableCodeCoverage YES \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 300 \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS=ClipboardHistory/ClipboardHistory.entitlements \
  CODE_SIGN_IDENTITY=- \
  -only-testing:ClipboardHistoryUITests test >"$evidence_root/UI.log" 2>&1; then
  cat "$evidence_root/UI.log" >&2
  print -u2 "coverage suite: UI run failed; evidence=$evidence_root"
  exit 1
fi
save_summary UI
python3 scripts/verify-test-inventory.py UI "$evidence_root/UI.xcresult"

scripts/merge-xcode-coverage.sh "$evidence_root"

unit_summary=$(cat "$evidence_root/UnitSummary.json")
ui_summary=$(cat "$evidence_root/UISummary.json")
unit_count=$(jq -r '.passedTests' <<<"$unit_summary")
ui_count=$(jq -r '.passedTests' <<<"$ui_summary")
[[ "$(jq -r '.result' <<<"$unit_summary")" == "Passed" ]]
[[ "$(jq -r '.result' <<<"$ui_summary")" == "Passed" ]]
print "coverage suite: unit=$unit_count ui=$ui_count"

scripts/verify-coverage.sh "$evidence_root/Combined.xccovreport"
suite_succeeded=1
