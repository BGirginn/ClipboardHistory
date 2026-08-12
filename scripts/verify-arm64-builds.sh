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
  helper="$app/Contents/Library/LoginItems/ClipboardHistoryLoginItem.app"
  xpc_service="$app/Contents/XPCServices/ClipboardHistoryBrowserAudioBridge.xpc"
  safari_extension="$app/Contents/PlugIns/ClipboardHistorySafariExtension.appex"
  [[ -d "$helper" ]] || {
    print -u2 "arm64 gate: embedded login helper is missing in $configuration"
    exit 1
  }
  [[ -d "$xpc_service" && -d "$safari_extension" ]] || {
    print -u2 "arm64 gate: embedded XPC service or Safari extension is missing in $configuration"
    exit 1
  }
  for executable in \
      "$app/Contents/MacOS/ClipboardHistory" \
      "$helper/Contents/MacOS/ClipboardHistoryLoginItem" \
      "$xpc_service/Contents/MacOS/ClipboardHistoryBrowserAudioBridge" \
      "$safari_extension/Contents/MacOS/ClipboardHistorySafariExtension"; do
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
  done
  minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")
  [[ "$minimum" == "14.2" ]] || {
    print -u2 "arm64 gate: $configuration minimum macOS is $minimum"
    exit 1
  }
  helper_minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$helper/Contents/Info.plist")
  [[ "$helper_minimum" == "14.2" ]] || {
    print -u2 "arm64 gate: $configuration helper minimum macOS is $helper_minimum"
    exit 1
  }
  for embedded_bundle in "$xpc_service" "$safari_extension"; do
    embedded_minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$embedded_bundle/Contents/Info.plist")
    [[ "$embedded_minimum" == "14.2" ]] || {
      print -u2 "arm64 gate: $configuration embedded component minimum macOS is $embedded_minimum"
      exit 1
    }
  done
done

print "arm64 gate: app, login helper, XPC service, and Safari extension are arm64-only with macOS 14.2 minimum in every configuration"
