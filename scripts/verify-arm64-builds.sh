#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
derived_data=$(mktemp -d /private/tmp/clipboardhistory-arm64-builds.XXXXXX)
trap 'rm -rf "$derived_data"' EXIT

cd "$repository_root"
for configuration in Debug Release CommunityRelease; do
  log="$derived_data/$configuration.log"
  if ! xcodebuild -quiet \
      -project ClipboardHistory.xcodeproj \
      -scheme ClipboardHistory \
      -configuration "$configuration" \
      -destination 'generic/platform=macOS' \
      -derivedDataPath "$derived_data" \
      ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build \
      >"$log" 2>&1; then
    sed -n '1,200p' "$log" >&2
    exit 1
  fi
  if rg -n '(^|[[:space:]])(warning|error):' "$log"; then
    print -u2 "arm64 gate: compiler, analyzer, or linker diagnostic in $configuration"
    exit 1
  fi

  app="$derived_data/Build/Products/$configuration/ClipboardHistory.app"
  executable="$app/Contents/MacOS/ClipboardHistory"
  architectures=$(lipo -archs "$executable")
  [[ "$architectures" == "arm64" ]] || {
    print -u2 "arm64 gate: $configuration architecture mismatch: $architectures"
    exit 1
  }
  file "$executable" | rg -q 'Mach-O 64-bit executable arm64' || {
    print -u2 "arm64 gate: file(1) did not identify an arm64 Mach-O for $configuration"
    exit 1
  }
  otool -hv "$executable" | rg -q 'ARM64' || {
    print -u2 "arm64 gate: otool did not identify ARM64 for $configuration"
    exit 1
  }
  minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
  [[ "$minimum" == "14.0" ]] || {
    print -u2 "arm64 gate: $configuration minimum macOS is $minimum"
    exit 1
  }
done

print "arm64 gate: Debug, Release, and CommunityRelease are arm64-only with macOS 14 minimum"
