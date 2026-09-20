#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h:h}
temporary_root=$(mktemp -d /private/tmp/coredeck-coverage-gate-test.XXXXXX)
trap 'rm -rf -- "$temporary_root"' EXIT
mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/xcrun" <<'SCRIPT'
#!/bin/zsh
cat "$COREDECK_TEST_COVERAGE_JSON"
SCRIPT
chmod +x "$temporary_root/bin/xcrun"
print '{"targets":[{"name":"ClipboardHistoryTestHost.app","lineCoverage":1,"files":[]}]}' \
  > "$temporary_root/report.json"
touch "$temporary_root/Combined.xccovreport"

if COREDECK_TEST_COVERAGE_JSON="$temporary_root/report.json" \
    PATH="$temporary_root/bin:$PATH" \
    "$repository_root/scripts/verify-coverage.sh" \
      "$temporary_root/Combined.xccovreport" > "$temporary_root/result.log" 2>&1; then
  print -u2 "coverage regression: missing production sources passed"
  exit 1
fi
rg -q 'coverage gate: production source is missing from the report:' \
  "$temporary_root/result.log"
print 'coverage regression: missing production sources fail the gate'

fixture_root="$temporary_root/fixture"
mkdir -p "$fixture_root/scripts" "$fixture_root/ClipboardHistory"
cp "$repository_root/scripts/verify-coverage.sh" "$fixture_root/scripts/verify-coverage.sh"
print 'protocol CoverageFixture {}' > "$fixture_root/ClipboardHistory/Fixture.swift"
fixture_hash=$(shasum -a 256 "$fixture_root/ClipboardHistory/Fixture.swift" | cut -d ' ' -f 1)
print "$fixture_hash\tClipboardHistory/Fixture.swift\tprotocol-only" \
  > "$fixture_root/scripts/coverage-nonexecutable-sources.tsv"

COREDECK_TEST_COVERAGE_JSON="$temporary_root/report.json" \
  PATH="$temporary_root/bin:$PATH" \
  "$fixture_root/scripts/verify-coverage.sh" \
    "$temporary_root/Combined.xccovreport" > "$temporary_root/fixture.log" 2>&1
rg -q 'coverage exemption: ClipboardHistory/Fixture.swift' "$temporary_root/fixture.log"

print 'func newlyExecutable() {}' >> "$fixture_root/ClipboardHistory/Fixture.swift"
if COREDECK_TEST_COVERAGE_JSON="$temporary_root/report.json" \
    PATH="$temporary_root/bin:$PATH" \
    "$fixture_root/scripts/verify-coverage.sh" \
      "$temporary_root/Combined.xccovreport" > "$temporary_root/stale.log" 2>&1; then
  print -u2 "coverage regression: changed audited source passed"
  exit 1
fi
rg -q 'coverage gate: audited source changed and needs review:' "$temporary_root/stale.log"
print 'coverage regression: content changes invalidate audited exemptions'
