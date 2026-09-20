#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-analyzer-test.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcodebuild" <<'SCRIPT'
#!/bin/zsh
if [[ "$1" == -version ]]; then
  print 'Xcode synthetic-test'
  exit 0
fi
while (( $# )); do
  if [[ "$1" == -resultBundlePath ]]; then
    shift
    [[ "$ANALYZER_SCENARIO" == missing ]] || mkdir -p "$1"
  fi
  shift
done
case "$ANALYZER_SCENARIO" in
  fail) print -u2 'synthetic analyzer failure'; exit 65 ;;
  warning) print 'warning: synthetic analyzer finding' ;;
esac
exit 0
SCRIPT
chmod +x "$temporary_root/bin/xcodebuild"
for scenario in fail warning missing passed; do
  if PATH="$temporary_root/bin:$PATH" ANALYZER_SCENARIO="$scenario" \
      COREDECK_EVIDENCE_ROOT="$temporary_root/$scenario" \
      "$repository_root/scripts/verify-analyzer.sh" > "$temporary_root/$scenario.log" 2>&1; then
    [[ "$scenario" == passed ]] || exit 1
  else
    [[ "$scenario" != passed ]] || exit 1
  fi
  evidence=("$temporary_root/$scenario"/analyzer.*)
  [[ ${#evidence} == 1 && -s "$evidence/Environment.json" && -f "$evidence/Analyze.log" ]]
done
print 'analyzer regression: failure, warnings and missing bundle rejected; logs retained'
