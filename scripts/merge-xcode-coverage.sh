#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1/Unit.xcresult" || ! -d "$1/UI.xcresult" ]]; then
  print -u2 "usage: $0 /path/to/evidence-with-Unit-and-UI.xcresult"
  exit 64
fi

evidence_root=${1:A}
for lane in Unit UI; do
  export_root="$evidence_root/${lane}Coverage"
  xcrun xcresulttool export coverage \
    --path "$evidence_root/$lane.xcresult" \
    --output-path "$export_root"
  report=$(find "$export_root" -maxdepth 1 -type f \
    \( -name '*CoverageReport' -o -name '*.xccovreport' \) -print -quit)
  archive=$(find "$export_root" -maxdepth 1 -type d \
    \( -name '*CoverageArchive' -o -name '*.xccovarchive' \) -print -quit)
  if [[ -z "$report" || -z "$archive" || ! -s "$report" ||
        -z "$(find "$archive" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    print -u2 "coverage merge: $lane export is incomplete"
    exit 1
  fi
  if [[ "$report" != "$export_root/$lane.xccovreport" ]]; then
    mv "$report" "$export_root/$lane.xccovreport"
  fi
  if [[ "$archive" != "$export_root/$lane.xccovarchive" ]]; then
    mv "$archive" "$export_root/$lane.xccovarchive"
  fi
done

xcrun xccov merge \
  --outReport "$evidence_root/Combined.xccovreport" \
  --outArchive "$evidence_root/Combined.xccovarchive" \
  "$evidence_root/UnitCoverage/Unit.xccovreport" \
  "$evidence_root/UnitCoverage/Unit.xccovarchive" \
  "$evidence_root/UICoverage/UI.xccovreport" \
  "$evidence_root/UICoverage/UI.xccovarchive"

if [[ ! -s "$evidence_root/Combined.xccovreport" ||
      ! -d "$evidence_root/Combined.xccovarchive" ||
      -z "$(find "$evidence_root/Combined.xccovarchive" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  print -u2 "coverage merge: merged report or archive is missing"
  exit 1
fi
print "coverage merge: unit and UI archives merged"
