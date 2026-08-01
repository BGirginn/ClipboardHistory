#!/bin/zsh
set -euo pipefail

identity_count=$(security find-identity -v -p codesigning | rg -c 'Apple Development:' || true)
if (( identity_count == 0 )); then
  print -u2 "development signing gate: Apple Development identity is missing"
  exit 1
fi

account_name=$(id -un)
user_directory=$(dscacheutil -q user -a name "$account_name" | awk '/^dir: / {print $2}')
[[ -n "$user_directory" ]] || {
  print -u2 "development signing gate: user directory could not be resolved"
  exit 1
}
profile_roots=(
  "$user_directory/Library/MobileDevice/Provisioning Profiles"
  "$user_directory/Library/Developer/Xcode/UserData/Provisioning Profiles"
)
temporary_directory=$(mktemp -d /private/tmp/clipboardhistory-profile.XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT

matched_profile=""
for root in "${profile_roots[@]}"; do
  [[ -d "$root" ]] || continue
  while IFS= read -r profile; do
    decoded="$temporary_directory/${profile:t}.plist"
    security cms -D -i "$profile" >"$decoded" 2>/dev/null || continue
    if plutil -extract Entitlements.keychain-access-groups xml1 -o - "$decoded" 2>/dev/null \
        | rg -q 'com\.brgirgin\.ClipboardHistory'; then
      matched_profile="$profile"
      break 2
    fi
  done < <(find "$root" -maxdepth 1 \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) -type f -print)
done

if [[ -z "$matched_profile" ]]; then
  print -u2 "development signing gate: no provisioning profile authorizes the ClipboardHistory keychain access group"
  exit 1
fi

print "development signing gate: Apple Development identity and matching Keychain profile are installed (${matched_profile:t})"
