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

derived_data=$(mktemp -d /private/tmp/clipboardhistory-community-build.XXXXXX)
trap 'rm -rf "$derived_data"' EXIT

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
"$repository_root/scripts/package-community-artifact.sh" "$source_app" "$output_directory"
