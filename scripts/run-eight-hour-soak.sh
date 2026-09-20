#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
  print -u2 "usage: COREDECK_SOAK_ISOLATED_ACCOUNT=1 $0 /path/to/CoreDeck.app /path/to/history.sqlite3 /empty/evidence-directory"
  exit 64
fi

repository_root=${0:A:h:h}
app=${1:A}
database=${2:A}
evidence=${3:A}
executable="$app/Contents/MacOS/CoreDeck"
expected_database="$HOME/Library/Application Support/ClipboardHistory/history.sqlite3"
[[ ${COREDECK_SOAK_ISOLATED_ACCOUNT:-0} == 1 ]] || {
  print -u2 "soak gate: run from an isolated test account with synthetic clipboard data"
  exit 1
}
[[ "$database" == "${expected_database:A}" ]] || {
  print -u2 "soak gate: database is not this account's CoreDeck database"
  exit 1
}
[[ -x "$executable" ]] || { print -u2 "soak gate: executable is missing"; exit 1; }
[[ ! -e "$evidence" || -z "$(find "$evidence" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
  print -u2 "soak gate: evidence directory must be empty"
  exit 1
}
mkdir -p "$evidence"
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence/Environment.json" soak "$executable"

"$executable" >"$evidence/application.log" 2>&1 &
pid=$!
finish() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
trap finish EXIT
sleep 60
kill -0 "$pid" 2>/dev/null || { print -u2 "soak gate: application exited during warm-up"; exit 1; }
[[ -f "$database" ]] || { print -u2 "soak gate: database is missing"; exit 1; }
[[ "$(stat -f %u "$database")" == "$(id -u)" ]] || {
  print -u2 "soak gate: database belongs to another user"
  exit 1
}

samples="$evidence/process-samples.csv"
print 'epoch,pid,cpu,rss_kb,identity,db_open,responsive' > "$samples"
deadline=$(( EPOCHSECONDS + 8 * 60 * 60 ))
while true; do
  kill -0 "$pid" 2>/dev/null || { print -u2 "soak gate: application exited"; exit 1; }
  command=$(ps -o command= -p "$pid")
  [[ "$command" == "$executable" ]] || {
    print -u2 "soak gate: sampled PID is not the launched CoreDeck executable"
    exit 1
  }
  /usr/sbin/lsof -a -p "$pid" -Fn -- "$database" | rg -Fxq "n$database" || {
    print -u2 "soak gate: sampled process does not own the expected database"
    exit 1
  }
  /usr/bin/perl -e 'alarm 10; exec @ARGV' /usr/bin/osascript \
    -e 'with timeout of 3 seconds' \
    -e "tell application \"System Events\" to get count of windows of (first application process whose unix id is $pid)" \
    -e 'end timeout' >"$evidence/last-health-check.txt" 2>&1 || {
      print -u2 "soak gate: application accessibility probe timed out or failed"
      exit 1
    }
  cpu=$(ps -o %cpu= -p "$pid" | tr -d ' ')
  rss=$(ps -o rss= -p "$pid" | tr -d ' ')
  print "$EPOCHSECONDS,$pid,$cpu,$rss,1,1,1" >> "$samples"
  (( EPOCHSECONDS >= deadline )) && break
  sleep 60
done

[[ "$(sqlite3 "$database" 'PRAGMA integrity_check;')" == "ok" ]] || {
  print -u2 "soak gate: SQLite integrity check failed"
  exit 1
}
/usr/bin/python3 "$repository_root/scripts/verify-soak-evidence.py" "$samples" \
  > "$evidence/summary.json"
cat "$evidence/summary.json"
print "soak gate: eight hours passed; CPU, RSS, process, responsiveness, and SQLite checks passed"
