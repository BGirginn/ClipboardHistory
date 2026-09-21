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

cd "$repository_root"
if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "artifact build: repository must be clean"
  exit 1
fi
source_commit=$(git rev-parse HEAD)

derived_data=$(mktemp -d /private/tmp/coredeck-community-build.XXXXXX)
trap 'rm -rf "$derived_data"' EXIT

xcodebuild -quiet \
  -project ClipboardHistory.xcodeproj \
  -scheme ClipboardHistory \
  -configuration CommunityRelease \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" build

source_app="$derived_data/Build/Products/CommunityRelease/CoreDeck.app"
"$repository_root/scripts/package-community-artifact.sh" "$source_app" "$output_directory"
print -r -- "$source_commit" > "$output_directory/source-commit.txt"
(
  cd "$output_directory"
  shasum -a 256 source-commit.txt >> SHA256SUMS
  shasum -a 256 -c SHA256SUMS >/dev/null
)
