#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
evidence_parent=${COREDECK_EVIDENCE_ROOT:-/private/tmp/coredeck-release-evidence}
mkdir -p "$evidence_parent"
evidence=$(mktemp -d "$evidence_parent/analyzer.XXXXXX")
trap 'rm -rf -- "$evidence/DerivedData"' EXIT
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence/Environment.json" analyzer
print "analyzer gate: evidence=$evidence"
if ! xcodebuild -quiet \
    -project "$repository_root/ClipboardHistory.xcodeproj" \
    -scheme ClipboardHistory -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$evidence/DerivedData" \
    -resultBundlePath "$evidence/Analyze.xcresult" \
    CODE_SIGNING_ALLOWED=NO analyze >"$evidence/Analyze.log" 2>&1; then
  cat "$evidence/Analyze.log" >&2
  exit 1
fi
if rg -n '(^|[[:space:]])(warning|error):' "$evidence/Analyze.log"; then
  print -u2 'analyzer gate: compiler or analyzer diagnostic emitted'
  exit 1
fi
[[ -d "$evidence/Analyze.xcresult" ]] || {
  print -u2 'analyzer gate: required result bundle is missing'
  exit 1
}
print 'analyzer gate: completed without diagnostics'
