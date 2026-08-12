#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 || ! -d "$1" ]]; then
  print -u2 "usage: $0 /path/to/ClipboardHistory.app /empty/output/directory"
  exit 64
fi

repository_root=${0:A:h:h}
source_app=${1:A}
output_directory=${2:A}
identity='ClipboardHistory Community Beta'
release_version='1.0.0-beta.4'
expected_build='10004'

if [[ -e "$output_directory" && -n "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  print -u2 "artifact packaging: output directory must be empty"
  exit 1
fi
mkdir -p "$output_directory"

"$repository_root/scripts/verify-community-signing.sh"
if ! command -v syft >/dev/null; then
  print -u2 "artifact packaging: syft is required for the SPDX SBOM"
  exit 1
fi

staging=$(mktemp -d /private/tmp/clipboardhistory-community-stage.XXXXXX)
trap 'rm -rf "$staging"' EXIT
artifact_app="$staging/ClipboardHistory.app"
ditto --noqtn "$source_app" "$artifact_app"

helper_app="$artifact_app/Contents/Library/LoginItems/ClipboardHistoryLoginItem.app"
xpc_service="$artifact_app/Contents/XPCServices/ClipboardHistoryBrowserAudioBridge.xpc"
safari_extension="$artifact_app/Contents/PlugIns/ClipboardHistorySafariExtension.appex"
for nested_bundle in "$helper_app" "$xpc_service" "$safari_extension"; do
  [[ -d "$nested_bundle" ]] || {
    print -u2 "artifact packaging: embedded bundle is missing: $nested_bundle"
    exit 1
  }
done

codesign --force --options runtime --timestamp=none --sign "$identity" "$helper_app"
codesign --force --options runtime --timestamp=none --sign "$identity" "$xpc_service"
codesign --force --options runtime --timestamp=none \
  --entitlements "$repository_root/ClipboardHistorySafariExtension/ClipboardHistorySafariExtension.entitlements" \
  --sign "$identity" "$safari_extension"
codesign --force --options runtime --timestamp=none \
  --entitlements "$repository_root/ClipboardHistory/ClipboardHistory.entitlements" \
  --sign "$identity" "$artifact_app"

codesign --verify --deep --strict --verbose=2 "$artifact_app"
codesign --verify --strict --verbose=2 "$helper_app"
helper_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$helper_app/Contents/Info.plist")
[[ "$helper_identifier" == "com.brgirgin.ClipboardHistory.LoginItem" ]] || {
  print -u2 "artifact packaging: login helper identifier mismatch: $helper_identifier"
  exit 1
}
codesign -d --entitlements :- "$artifact_app" 2>/dev/null \
  | plutil -convert json -o - - \
  | jq -e 'length == 0' >/dev/null || {
    print -u2 "artifact packaging: CommunityRelease contains an unexpected entitlement"
    exit 1
  }

architectures=$(lipo -archs "$artifact_app/Contents/MacOS/ClipboardHistory")
[[ "$architectures" == "arm64" ]] || {
  print -u2 "artifact packaging: arm64-only verification failed: $architectures"
  exit 1
}
helper_architectures=$(lipo -archs "$helper_app/Contents/MacOS/ClipboardHistoryLoginItem")
[[ "$helper_architectures" == "arm64" ]] || {
  print -u2 "artifact packaging: login helper arm64-only verification failed: $helper_architectures"
  exit 1
}
minimum_os=$(otool -l "$artifact_app/Contents/MacOS/ClipboardHistory" \
  | awk '$1 == "minos" { print $2; exit }')
[[ "$minimum_os" == "14.2" ]] || {
  print -u2 "artifact packaging: minimum macOS mismatch: $minimum_os"
  exit 1
}
helper_minimum_os=$(otool -l "$helper_app/Contents/MacOS/ClipboardHistoryLoginItem" \
  | awk '$1 == "minos" { print $2; exit }')
[[ "$helper_minimum_os" == "14.2" ]] || {
  print -u2 "artifact packaging: login helper minimum macOS mismatch: $helper_minimum_os"
  exit 1
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$artifact_app/Contents/Info.plist")
beta=$(/usr/libexec/PlistBuddy -c 'Print :ClipboardHistoryBetaVersion' "$artifact_app/Contents/Info.plist")
[[ "$version" == "1.0.0" && "$build" == "$expected_build" && "$beta" == "$release_version" ]] || {
  print -u2 "artifact packaging: version mismatch: $version ($build), $beta"
  exit 1
}

zip="$output_directory/ClipboardHistory-$release_version-arm64.zip"
dmg="$output_directory/ClipboardHistory-$release_version-arm64.dmg"
spdx="$output_directory/ClipboardHistory-$release_version-arm64.spdx.json"
ditto -c -k --sequesterRsrc --keepParent "$artifact_app" "$zip"
hdiutil create -quiet -fs HFS+ -srcfolder "$artifact_app" -volname "ClipboardHistory $release_version" "$dmg"
hdiutil verify "$dmg" >/dev/null
unzip -tq "$zip" >/dev/null
syft scan "dir:$artifact_app" \
  --source-name ClipboardHistory \
  --source-version "$release_version" \
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
  print -u2 "artifact packaging: designated requirement extraction failed"
  exit 1
}
print -r -- "$designated_requirement" > "$output_directory/designated-requirement.txt"
codesign --verify -R "=$requirement" "$artifact_app"
security find-certificate -c "$identity" -p \
  | openssl x509 -noout -fingerprint -sha256 \
  > "$output_directory/signing-certificate-sha256.txt"

print "artifact packaging: created signed arm64 ZIP, DMG, checksums, SBOM, requirement, and certificate fingerprint"
