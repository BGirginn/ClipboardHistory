#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-arm64-failure.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
print -u2 'synthetic arm64 build failure'
exit 65
SCRIPT
chmod +x "$temporary_root/bin/xcodebuild"
if PATH="$temporary_root/bin:$PATH" COREDECK_EVIDENCE_ROOT="$temporary_root/evidence" \
    "$repository_root/scripts/verify-arm64-builds.sh" > "$temporary_root/command.log" 2>&1; then
  print -u2 'arm64 failure regression: failed build passed'
  exit 1
fi
evidence=("$temporary_root"/evidence/arm64-builds.*)
[[ ${#evidence} == 1 ]]
rg -q 'synthetic arm64 build failure' "$evidence/Debug.log"
[[ -s "$evidence/Environment.json" ]]
[[ ! -e "$evidence/DerivedData" ]]
print 'arm64 failure regression: metadata and full build log retained'
