#!/bin/zsh
set -euo pipefail

usage() {
  print -u2 "usage: $0 [--dry-run | --prune | --auto | --clean]"
}

mode=${1:---dry-run}
if (( $# > 1 )); then
  usage
  exit 64
fi
case "$mode" in
  --dry-run|--prune|--auto|--clean) ;;
  *)
    usage
    exit 64
    ;;
esac

repository_root=${CLIPBOARD_HISTORY_REPOSITORY_ROOT:-${0:A:h:h}}
temporary_root=${CLIPBOARD_HISTORY_TEMP_ROOT:-/private/tmp}
derived_data_root=${CLIPBOARD_HISTORY_DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}
maximum_temporary_kib=${CLIPBOARD_HISTORY_MAX_TEMP_KIB:-2097152}
maximum_development_kib=${CLIPBOARD_HISTORY_MAX_DEVELOPMENT_KIB:-2097152}
maximum_derived_data_kib=${CLIPBOARD_HISTORY_MAX_DERIVED_DATA_KIB:-4194304}
minimum_age_minutes=${CLIPBOARD_HISTORY_MINIMUM_AGE_MINUTES:-30}
stale_temporary_hours=${CLIPBOARD_HISTORY_STALE_TEMP_HOURS:-24}
stale_development_days=${CLIPBOARD_HISTORY_STALE_DEVELOPMENT_DAYS:-7}
stale_derived_data_days=${CLIPBOARD_HISTORY_STALE_DERIVED_DATA_DAYS:-7}

for value in \
  "$maximum_temporary_kib" \
  "$maximum_development_kib" \
  "$maximum_derived_data_kib" \
  "$minimum_age_minutes" \
  "$stale_temporary_hours" \
  "$stale_development_days" \
  "$stale_derived_data_days"; do
  if [[ "$value" != <-> ]]; then
    print -u2 "artifact cleanup: limits must be non-negative integers"
    exit 64
  fi
done

temporary_root=${temporary_root:A}
derived_data_root=${derived_data_root:A}
repository_root=${repository_root:A}
development_root="$repository_root/.build/DevelopmentTests"
now=$(/bin/date +%s)
minimum_age_seconds=$(( minimum_age_minutes * 60 ))
stale_temporary_seconds=$(( stale_temporary_hours * 60 * 60 ))
stale_development_seconds=$(( stale_development_days * 24 * 60 * 60 ))
stale_derived_data_seconds=$(( stale_derived_data_days * 24 * 60 * 60 ))
removed_count=0
freed_kib=0
planned_count=0
planned_kib=0
typeset -A planned_removals
process_snapshot=$(/bin/ps -axo command= 2>/dev/null || true)

setopt null_glob

item_size_kib() {
  local item=$1
  local measurement
  measurement=$(/usr/bin/du -sk "$item" 2>/dev/null || print "0")
  REPLY=${measurement%%[[:space:]]*}
  [[ "$REPLY" == <-> ]] || REPLY=0
}

item_modification_time() {
  local item=$1
  REPLY=$(/usr/bin/stat -f %m "$item" 2>/dev/null || print "0")
  [[ "$REPLY" == <-> ]] || REPLY=0
}

item_age_seconds() {
  item_modification_time "$1"
  REPLY=$(( now - REPLY ))
  (( REPLY >= 0 )) || REPLY=0
}

item_is_active() {
  local item=$1
  local active_location
  for active_location in \
    "${BUILD_ROOT:-}" \
    "${CONFIGURATION_BUILD_DIR:-}" \
    "${OBJROOT:-}" \
    "${PROJECT_TEMP_DIR:-}" \
    "${SYMROOT:-}" \
    "${TARGET_BUILD_DIR:-}"; do
    [[ -n "$active_location" ]] || continue
    active_location=${active_location:A}
    if [[ "$active_location" == "$item" || "$active_location" == "$item"/* ]]; then
      return 0
    fi
  done
  [[ -n "$process_snapshot" && "$process_snapshot" == *"$item"* ]]
}

item_is_owned_regular_path() {
  local item=$1
  [[ -e "$item" && ! -L "$item" && -O "$item" ]]
}

safe_remove() {
  local item=${1:A}
  local allowed_root=${2:A}
  local reason=$3

  if [[ "$item" == "$allowed_root" || "$item" != "$allowed_root"/* ]]; then
    print -u2 "artifact cleanup: refused path outside managed root: $item"
    return 1
  fi
  item_is_owned_regular_path "$item" || return 0
  if item_is_active "$item"; then
    [[ "$mode" == "--auto" ]] || print "artifact cleanup: kept active path $item"
    return 0
  fi

  item_size_kib "$item"
  local size_kib=$REPLY
  if [[ "$mode" == "--dry-run" ]]; then
    planned_removals[$item]=1
    (( planned_count += 1 ))
    planned_kib=$(( planned_kib + size_kib ))
    print "artifact cleanup: would remove $item ($reason, ${size_kib} KiB)"
    return 0
  fi

  /bin/rm -rf -- "$item"
  (( removed_count += 1 ))
  freed_kib=$(( freed_kib + size_kib ))
  print "artifact cleanup: removed $item ($reason, ${size_kib} KiB)"
}

is_known_temporary_artifact() {
  case ${1:t} in
    clipboardhistory-arm64-builds.*|\
    clipboardhistory-community-build.*|\
    clipboardhistory-community-stage.*|\
    clipboardhistory-coverage-*|\
    clipboardhistory-coverage.*.json|\
    clipboardhistory-localization.*|\
    clipboardhistory-mutation-*.*|\
    clipboardhistory-performance.*|\
    clipboardhistory-sanitizers.*|\
    clipboardhistory-signing.*|\
    ClipboardAssetStoreCoverageTests-*|\
    ClipboardDragProviderTests-*|\
    ClipboardHistoryCollections-*|\
    ClipboardHistoryDirectPaste-*|\
    ClipboardHistoryEditing-*|\
    ClipboardHistoryFailClosed-*|\
    ClipboardHistoryInjectedSQLite-*|\
    ClipboardHistoryKeyFailure-*|\
    ClipboardHistoryPastePermission-*|\
    ClipboardHistoryPasteStack-*|\
    ClipboardHistoryCoverage*|\
    ClipboardHistoryTamperedText-*|\
    ClipboardHistoryTests-*|\
    ClipboardHistory-UITesting-*|\
    ClipboardHistory-UITests-*|\
    ClipboardHistoryViewModelSQLiteFailure-*|\
    ClipboardHistoryViewModelTests-*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_temporary_xcode_derived_data() {
  local item=$1
  case ${item:t} in
    ClipboardHistory*|clipboardhistory*) ;;
    *) return 1 ;;
  esac

  [[ -d "$item/Build/Intermediates.noindex" || \
     -d "$item/Build/Products" || \
     -d "$item/Index.noindex" || \
     -d "$item/Logs/Build" ]]
}

temporary_candidates=()
if [[ -d "$temporary_root" ]]; then
  for item in "$temporary_root"/*(N); do
    if is_known_temporary_artifact "$item" || is_temporary_xcode_derived_data "$item"; then
      temporary_candidates+=("$item")
    fi
  done
fi

if [[ "$mode" == "--clean" ]]; then
  for item in "${temporary_candidates[@]}"; do
    safe_remove "$item" "$temporary_root" "explicit clean"
  done
else
  for item in "${temporary_candidates[@]}"; do
    [[ -e "$item" ]] || continue
    item_age_seconds "$item"
    if (( REPLY >= stale_temporary_seconds )); then
      safe_remove "$item" "$temporary_root" "older than ${stale_temporary_hours}h"
    fi
  done

  total_temporary_kib=0
  for item in "${temporary_candidates[@]}"; do
    [[ -e "$item" ]] || continue
    [[ -z ${planned_removals[$item]-} ]] || continue
    item_size_kib "$item"
    total_temporary_kib=$(( total_temporary_kib + REPLY ))
  done

  while (( total_temporary_kib > maximum_temporary_kib )); do
    oldest_item=""
    oldest_time=$now
    for item in "${temporary_candidates[@]}"; do
      [[ -e "$item" ]] || continue
      [[ -z ${planned_removals[$item]-} ]] || continue
      item_age_seconds "$item"
      (( REPLY >= minimum_age_seconds )) || continue
      item_is_active "$item" && continue
      item_modification_time "$item"
      if (( REPLY <= oldest_time )); then
        oldest_time=$REPLY
        oldest_item=$item
      fi
    done
    [[ -n "$oldest_item" ]] || break

    item_size_kib "$oldest_item"
    oldest_size_kib=$REPLY
    safe_remove "$oldest_item" "$temporary_root" "temporary artifacts exceeded $maximum_temporary_kib KiB"
    if [[ "$mode" != "--dry-run" && -e "$oldest_item" ]]; then
      break
    fi
    total_temporary_kib=$(( total_temporary_kib - oldest_size_kib ))
  done

  if (( total_temporary_kib > maximum_temporary_kib )) && [[ "$mode" != "--auto" ]]; then
    print "artifact cleanup: temporary artifacts remain above the limit because only recent or active paths remain"
  fi
fi

if [[ -d "$development_root" ]]; then
  item_age_seconds "$development_root"
  development_age=$REPLY
  item_size_kib "$development_root"
  development_size_kib=$REPLY
  if [[ "$mode" == "--clean" ]]; then
    safe_remove "$development_root" "$repository_root/.build" "explicit clean"
  elif (( development_age >= stale_development_seconds )); then
    safe_remove "$development_root" "$repository_root/.build" "unused for ${stale_development_days}d"
  elif (( development_size_kib > maximum_development_kib && development_age >= minimum_age_seconds )); then
    safe_remove "$development_root" "$repository_root/.build" "development cache exceeded $maximum_development_kib KiB"
  fi
fi

derived_data_candidates=()
if [[ -d "$derived_data_root" ]]; then
  derived_data_candidates=("$derived_data_root"/ClipboardHistory-*(N))
fi

if [[ "$mode" == "--clean" ]]; then
  for item in "${derived_data_candidates[@]}"; do
    safe_remove "$item" "$derived_data_root" "explicit clean"
  done
else
  for item in "${derived_data_candidates[@]}"; do
    [[ -e "$item" ]] || continue
    item_age_seconds "$item"
    if (( REPLY >= stale_derived_data_seconds )); then
      safe_remove "$item" "$derived_data_root" "unused for ${stale_derived_data_days}d"
    fi
  done

  total_derived_data_kib=0
  for item in "${derived_data_candidates[@]}"; do
    [[ -e "$item" ]] || continue
    [[ -z ${planned_removals[$item]-} ]] || continue
    item_size_kib "$item"
    total_derived_data_kib=$(( total_derived_data_kib + REPLY ))
  done

  while (( total_derived_data_kib > maximum_derived_data_kib )); do
    oldest_item=""
    oldest_time=$now
    for item in "${derived_data_candidates[@]}"; do
      [[ -e "$item" ]] || continue
      [[ -z ${planned_removals[$item]-} ]] || continue
      item_age_seconds "$item"
      (( REPLY >= minimum_age_seconds )) || continue
      item_is_active "$item" && continue
      item_modification_time "$item"
      if (( REPLY <= oldest_time )); then
        oldest_time=$REPLY
        oldest_item=$item
      fi
    done
    [[ -n "$oldest_item" ]] || break

    item_size_kib "$oldest_item"
    oldest_size_kib=$REPLY
    safe_remove "$oldest_item" "$derived_data_root" "project DerivedData exceeded $maximum_derived_data_kib KiB"
    if [[ "$mode" != "--dry-run" && -e "$oldest_item" ]]; then
      break
    fi
    total_derived_data_kib=$(( total_derived_data_kib - oldest_size_kib ))
  done

  if (( total_derived_data_kib > maximum_derived_data_kib )) && [[ "$mode" != "--auto" ]]; then
    print "artifact cleanup: project DerivedData remains above the limit because only recent or active paths remain"
  fi
fi

if [[ -d "$repository_root/.build" ]]; then
  /bin/rmdir "$repository_root/.build" 2>/dev/null || true
fi

if (( removed_count > 0 )); then
  print "artifact cleanup: removed=$removed_count freed=${freed_kib} KiB"
elif (( planned_count > 0 )); then
  print "artifact cleanup: planned=$planned_count reclaimable=${planned_kib} KiB"
elif [[ "$mode" != "--auto" ]]; then
  print "artifact cleanup: nothing eligible for removal"
fi
