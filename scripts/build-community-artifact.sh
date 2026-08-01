#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  print -u2 "usage: $0 'ClipboardHistory Community Beta' /empty/output/directory"
  exit 64
fi

repository_root=${0:A:h:h}
identity=$1
output_directory=${2:A}
if [[ -e "$output_directory" && -n "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  print -u2 "artifact build: output directory must be empty"
  exit 1
fi
mkdir -p "$output_directory"

if ! security find-identity -v -p codesigning | rg -Fq "\"$identity\""; then
  print -u2 "artifact build: signing identity not found: $identity"
  exit 1
fi
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

architectures=$(lipo -archs "$artifact_app/Contents/MacOS/ClipboardHistory")
[[ "$architectures" == "arm64" ]] || {
  print -u2 "artifact build: arm64-only verification failed: $architectures"
  exit 1
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$artifact_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$artifact_app/Contents/Info.plist")
beta=$(/usr/libexec/PlistBuddy -c 'Print :ClipboardHistoryBetaVersion' "$artifact_app/Contents/Info.plist")
[[ "$version" == "1.0.0" && "$build" == "10001" && "$beta" == "1.0.0-beta.1" ]] || {
  print -u2 "artifact build: version mismatch: $version ($build), $beta"
  exit 1
}

zip="$output_directory/ClipboardHistory-1.0.0-beta.1-arm64.zip"
dmg="$output_directory/ClipboardHistory-1.0.0-beta.1-arm64.dmg"
ditto -c -k --sequesterRsrc --keepParent "$artifact_app" "$zip"
hdiutil create -quiet -fs HFS+ -srcfolder "$artifact_app" -volname 'ClipboardHistory 1.0.0-beta.1' "$dmg"
syft "dir:$artifact_app" -o "spdx-json=$output_directory/ClipboardHistory-1.0.0-beta.1-arm64.spdx.json"
shasum -a 256 "$zip" "$dmg" "$output_directory/ClipboardHistory-1.0.0-beta.1-arm64.spdx.json" > "$output_directory/SHA256SUMS"
codesign -d -r- "$artifact_app" 2> "$output_directory/designated-requirement.txt"
security find-certificate -c "$identity" -p \
  | openssl x509 -noout -fingerprint -sha256 \
  > "$output_directory/signing-certificate-sha256.txt"

print "artifact build: created signed arm64 ZIP, DMG, checksums, SBOM, requirement, and certificate fingerprint"
