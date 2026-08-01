#!/bin/zsh
set -euo pipefail

if [[ $# -ne 3 ]]; then
  print -u2 "usage: $0 /path/to/ClipboardHistory.app /path/to/history.sqlite3 /empty/evidence-directory"
  exit 64
fi

app=${1:A}
database=${2:A}
evidence=${3:A}
executable="$app/Contents/MacOS/ClipboardHistory"
[[ -x "$executable" ]] || { print -u2 "soak gate: executable is missing"; exit 1; }
[[ ! -e "$evidence" || -z "$(find "$evidence" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
  print -u2 "soak gate: evidence directory must be empty"
  exit 1
}
mkdir -p "$evidence"

"$executable" >"$evidence/application.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
sleep 60
kill -0 "$pid"
initial_rss=$(ps -o rss= -p "$pid" | tr -d ' ')
start=$EPOCHSECONDS
deadline=$(( start + 8 * 60 * 60 ))

while (( EPOCHSECONDS < deadline )); do
  kill -0 "$pid" || { print -u2 "soak gate: application exited"; exit 1; }
  ps -o lstart=,pid=,%cpu=,rss=,command= -p "$pid" >>"$evidence/process-samples.txt"
  sleep 60
done

final_rss=$(ps -o rss= -p "$pid" | tr -d ' ')
maximum_rss=$(( initial_rss + initial_rss / 10 ))
(( final_rss <= maximum_rss )) || {
  print -u2 "soak gate: RSS grew more than 10%: $initial_rss -> $final_rss KB"
  exit 1
}
[[ -f "$database" ]] || { print -u2 "soak gate: database is missing"; exit 1; }
[[ "$(sqlite3 "$database" 'PRAGMA integrity_check;')" == "ok" ]] || {
  print -u2 "soak gate: SQLite integrity check failed"
  exit 1
}
print "soak gate: eight hours passed, RSS growth <=10%, SQLite integrity_check=ok"
