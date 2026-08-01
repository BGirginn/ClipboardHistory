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

cd "$repository_root"
xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$evidence_root/UnitDerivedData" \
  -resultBundlePath "$evidence_root/Unit.xcresult" \
  -enableCodeCoverage YES \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:ClipboardHistoryTests test

# The production entitlement file is empty, so the isolated UI run can use an
# ad-hoc signature without an Apple account or provisioning profile.
xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$evidence_root/UIDerivedData" \
  -resultBundlePath "$evidence_root/UI.xcresult" \
  -enableCodeCoverage YES \
  ENABLE_DEBUG_DYLIB=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS=ClipboardHistory/ClipboardHistory.entitlements \
  CODE_SIGN_IDENTITY=- \
  -only-testing:ClipboardHistoryUITests test

xcrun xcresulttool export coverage \
  --path "$evidence_root/Unit.xcresult" \
  --output-path "$evidence_root/UnitCoverage"
xcrun xcresulttool export coverage \
  --path "$evidence_root/UI.xcresult" \
  --output-path "$evidence_root/UICoverage"

unit_report=$(find "$evidence_root/UnitCoverage" -maxdepth 1 -name '*CoverageReport' -print -quit)
unit_archive=$(find "$evidence_root/UnitCoverage" -maxdepth 1 -name '*CoverageArchive' -print -quit)
ui_report=$(find "$evidence_root/UICoverage" -maxdepth 1 -name '*CoverageReport' -print -quit)
ui_archive=$(find "$evidence_root/UICoverage" -maxdepth 1 -name '*CoverageArchive' -print -quit)
for artifact in "$unit_report" "$unit_archive" "$ui_report" "$ui_archive"; do
  [[ -n "$artifact" ]] || {
    print -u2 "coverage suite: xccov export is incomplete"
    exit 1
  }
done

xcrun xccov merge \
  --outReport "$evidence_root/Combined.xccovreport" \
  --outArchive "$evidence_root/Combined.xccovarchive" \
  "$unit_report" "$unit_archive" "$ui_report" "$ui_archive"

unit_summary=$(xcrun xcresulttool get test-results summary --path "$evidence_root/Unit.xcresult")
ui_summary=$(xcrun xcresulttool get test-results summary --path "$evidence_root/UI.xcresult")
unit_count=$(jq -r '.passedTests' <<<"$unit_summary")
ui_count=$(jq -r '.passedTests' <<<"$ui_summary")
[[ "$(jq -r '.result' <<<"$unit_summary")" == "Passed" ]]
[[ "$(jq -r '.result' <<<"$ui_summary")" == "Passed" ]]
print "coverage suite: unit=$unit_count ui=$ui_count"

scripts/verify-coverage.sh "$evidence_root/Combined.xccovreport"
