#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: $0 /path/to/combined.xccovreport-or-xcresult"
  exit 64
fi

repository_root=${0:A:h:h}
cd "$repository_root"
scripts/verify-static-quality.sh
scripts/verify-release-security.sh
scripts/verify-coverage.sh "$1"
scripts/verify-arm64-builds.sh
scripts/verify-sanitizers.sh
scripts/verify-performance.sh
scripts/run-critical-mutations.sh

if git status --porcelain | rg -n '(^|/)(\.env|.*\.p12|.*\.mobileprovision|.*private.*key)' -i; then
  print -u2 "release gate: possible credential artifact is present"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "release gate: working tree must be clean"
  exit 1
fi

print "release gate: local source gates passed; signed UI, OS matrix, soak, and clean distribution remain external gates"
