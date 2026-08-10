#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: $0 /empty/output/directory"
  exit 64
fi

repository_root=${0:A:h:h}
identity='ClipboardHistory Community Beta'
output_directory=${1:A}
if [[ -e "$output_directory" && -n "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  print -u2 "artifact build: output directory must be empty"
  exit 1
fi
mkdir -p "$output_directory"

"$repository_root/scripts/verify-community-signing.sh"
if ! command -v syft >/dev/null; then
  print -u2 "artifact build: syft is required for the SPDX SBOM"
  exit 1
fi

derived_data=$(mktemp -d /private/tmp/clipboardhistory-community-build.XXXXXX)
staging=$(mktemp -d /private/tmp/clipboardhistory-community-stage.XXXXXX)
trap 'rm -rf "$derived_data" "$staging"' EXIT

cd "$repository_root"
xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration CommunityRelease \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" build

source_app="$derived_data/Build/Products/CommunityRelease/ClipboardHistory.app"
artifact_app="$staging/ClipboardHistory.app"
ditto --noqtn "$source_app" "$artifact_app"
codesign --verify --deep --strict --verbose=2 "$artifact_app"
helper_app="$artifact_app/Contents/Library/LoginItems/ClipboardHistoryLoginItem.app"
[[ -d "$helper_app" ]] || {
  print -u2 "artifact build: signed login helper is missing"
  exit 1
}
codesign --verify --strict --verbose=2 "$helper_app"
helper_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$helper_app/Contents/Info.plist")
[[ "$helper_identifier" == "com.brgirgin.ClipboardHistory.LoginItem" ]] || {
  print -u2 "artifact build: login helper identifier mismatch: $helper_identifier"
  exit 1
}
codesign -d --entitlements :- "$artifact_app" 2>/dev/null \
  | plutil -convert json -o - - \
  | jq -e 'length == 0' >/dev/null || {
    print -u2 "artifact build: CommunityRelease contains an unexpected entitlement"
    exit 1
  }

architectures=$(lipo -archs "$artifact_app/Contents/MacOS/ClipboardHistory")
[[ "$architectures" == "arm64" ]] || {
  print -u2 "artifact build: arm64-only verification failed: $architectures"
  exit 1
}
helper_architectures=$(lipo -archs "$helper_app/Contents/MacOS/ClipboardHistoryLoginItem")
[[ "$helper_architectures" == "arm64" ]] || {
  print -u2 "artifact build: login helper arm64-only verification failed: $helper_architectures"
  exit 1
}
minimum_os=$(otool -l "$artifact_app/Contents/MacOS/ClipboardHistory" \
  | awk '$1 == "minos" { print $2; exit }')
[[ "$minimum_os" == "14.2" ]] || {
  print -u2 "artifact build: minimum macOS mismatch: $minimum_os"
  exit 1
}
helper_minimum_os=$(otool -l "$helper_app/Contents/MacOS/ClipboardHistoryLoginItem" \
  | awk '$1 == "minos" { print $2; exit }')
[[ "$helper_minimum_os" == "14.2" ]] || {
  print -u2 "artifact build: login helper minimum macOS mismatch: $helper_minimum_os"
  exit 1
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$artifact_app/Contents/Info.plist")
beta=$(/usr/libexec/PlistBuddy -c 'Print :ClipboardHistoryBetaVersion' "$artifact_app/Contents/Info.plist")
[[ "$version" == "1.0.0" && "$build" == "10002" && "$beta" == "1.0.0-beta.2" ]] || {
  print -u2 "artifact build: version mismatch: $version ($build), $beta"
  exit 1
}

zip="$output_directory/ClipboardHistory-1.0.0-beta.2-arm64.zip"
dmg="$output_directory/ClipboardHistory-1.0.0-beta.2-arm64.dmg"
spdx="$output_directory/ClipboardHistory-1.0.0-beta.2-arm64.spdx.json"
ditto -c -k --sequesterRsrc --keepParent "$artifact_app" "$zip"
hdiutil create -quiet -fs HFS+ -srcfolder "$artifact_app" -volname 'ClipboardHistory 1.0.0-beta.2' "$dmg"
hdiutil verify "$dmg" >/dev/null
unzip -tq "$zip" >/dev/null
syft scan "dir:$artifact_app" \
  --source-name ClipboardHistory \
  --source-version 1.0.0-beta.2 \
  -o "spdx-json=$spdx"
jq -e '.spdxVersion == "SPDX-2.3" and .name == "ClipboardHistory"' "$spdx" >/dev/null
(
  cd "$output_directory"
  shasum -a 256 "${zip:t}" "${dmg:t}" "${spdx:t}" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS >/dev/null
)
designated_requirement=$(codesign -d -r- "$artifact_app" 2>/dev/null)
requirement=${designated_requirement#designated => }
[[ "$requirement" != "$designated_requirement" ]] || {
  print -u2 "artifact build: designated requirement extraction failed"
  exit 1
}
print -r -- "$designated_requirement" > "$output_directory/designated-requirement.txt"
codesign --verify -R "=$requirement" "$artifact_app"
security find-certificate -c "$identity" -p \
  | openssl x509 -noout -fingerprint -sha256 \
  > "$output_directory/signing-certificate-sha256.txt"

print "artifact build: created signed arm64 ZIP, DMG, checksums, SBOM, requirement, and certificate fingerprint"
