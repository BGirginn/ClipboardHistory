#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-coverage-merge-test.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
set -euo pipefail
if [[ "$1 $2 $3" == 'xcresulttool export coverage' ]]; then
  output=${@: -1}
  lane=${${output:t}%Coverage}
  mkdir -p "$output"
  print report > "$output/${lane}CoverageReport"
  if [[ "${COREDECK_TEST_EXPORT_MODE:-}" != missing-ui-archive || "$lane" != UI ]]; then
    mkdir -p "$output/${lane}CoverageArchive"
    print archive > "$output/${lane}CoverageArchive/Index"
  fi
  exit 0
fi
if [[ "$1 $2" == 'xccov merge' ]]; then
  shift 2
  while (( $# )); do
    case "$1" in
      --outReport) report=$2; shift 2 ;;
      --outArchive) archive=$2; shift 2 ;;
      *) [[ ( -s "$1" && "$1" == *.xccovreport ) ||
            ( -d "$1" && "$1" == *.xccovarchive ) ]]; shift ;;
    esac
  done
  if [[ "${COREDECK_TEST_MERGE_MODE:-}" != no-output ]]; then
    print merged > "$report"
    mkdir -p "$archive"
    print merged > "$archive/Index"
  fi
  exit 0
fi
exit 64
SCRIPT
chmod +x "$temporary_root/bin/xcrun"

prepare_result() {
  mkdir -p "$temporary_root/$1/Unit.xcresult" "$temporary_root/$1/UI.xcresult"
}

prepare_result passed
PATH="$temporary_root/bin:$PATH" \
  "$repository_root/scripts/merge-xcode-coverage.sh" "$temporary_root/passed" \
  > "$temporary_root/passed.log" 2>&1
[[ -s "$temporary_root/passed/Combined.xccovreport" &&
   -d "$temporary_root/passed/Combined.xccovarchive" &&
   -s "$temporary_root/passed/Combined.xccovarchive/Index" ]]

prepare_result incomplete
if COREDECK_TEST_EXPORT_MODE=missing-ui-archive PATH="$temporary_root/bin:$PATH" \
    "$repository_root/scripts/merge-xcode-coverage.sh" "$temporary_root/incomplete" \
    > "$temporary_root/incomplete.log" 2>&1; then
  print -u2 'coverage merge regression: incomplete UI export passed'
  exit 1
fi
rg -q 'coverage merge: UI export is incomplete' "$temporary_root/incomplete.log"

prepare_result no_output
if COREDECK_TEST_MERGE_MODE=no-output PATH="$temporary_root/bin:$PATH" \
    "$repository_root/scripts/merge-xcode-coverage.sh" "$temporary_root/no_output" \
    > "$temporary_root/no_output.log" 2>&1; then
  print -u2 'coverage merge regression: missing merged artifact passed'
  exit 1
fi
rg -q 'coverage merge: merged report or archive is missing' "$temporary_root/no_output.log"
print 'coverage merge regression: extensionless exports merge; missing artifacts fail'
