#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
cd "$repository_root"
pattern='/Users/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}'
allowed_public_fixtures='BEGIN PRIVATE KEY.*format|explicit `BEGIN PRIVATE KEY`|`BEGIN PRIVATE KEY`|/Users/\.\.\./Project-X/Client-Y/\.\.\.|-----BEGIN PRIVATE KEY-----\\nYWJjZA==\\n-----END PRIVATE KEY-----|/Users/example/Secret Project/plan\.pdf'

working_tree_matches=$(
  rg -n -I -e "$pattern" . --hidden -g '!.git/**' -g '!scripts/verify-release-security.sh' \
    | rg -v "$allowed_public_fixtures" \
    || true
)
if [[ -n "$working_tree_matches" ]]; then
  print -u2 "release security gate: path or credential-shaped content in working tree"
  print -u2 -r -- "$working_tree_matches"
  exit 1
fi

# The initial commit contains four documented detector fixtures made from
# public example values. Match only those exact strings; all other hits fail.
history_matches=$(
  git grep -n -I -E "$pattern" $(git rev-list --all) -- . ':(exclude)scripts/verify-release-security.sh' 2>/dev/null \
    | rg -v "ghp_abcdefghijklmnopqrstuvwxyz123456|xoxb-1234567890-abcdefghijklmnopqrstuvwxyz|AKIAIOSFODNN7EXAMPLE|BEGIN OPENSSH PRIVATE KEY.*\\\\nabc|$allowed_public_fixtures" \
    || true
)
if [[ -n "$history_matches" ]]; then
  print -u2 "release security gate: path or credential-shaped content in Git history"
  print -u2 -r -- "$history_matches"
  exit 1
fi

if find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './build' -prune -o \
    \( -iname '*.p12' -o -iname '*.mobileprovision' -o -iname '*.provisionprofile' -o -iname '*private*key*' \) -print \
    | rg -q .; then
  print -u2 "release security gate: signing or private-key artifact in repository"
  exit 1
fi

print "release security gate: working tree and Git history scan passed"
