#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
temporary_directory=$(mktemp -d /private/tmp/clipboardhistory-localization.XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT

cd "$repository_root"
xcrun xcstringstool extract \
  --SwiftUI \
  --modern-localizable-strings \
  --output-format xcstrings \
  --output-directory "$temporary_directory" \
  $(rg --files ClipboardHistory -g '*.swift')

fresh="$temporary_directory/Localizable.xcstrings"
catalog="ClipboardHistory/Localizable.xcstrings"
translations="scripts/tr-localizations.json"

jq -e 'type == "object" and all(.[]; type == "string" and length > 0)' "$translations" >/dev/null
missing=$(jq -r --slurpfile tr "$translations" '.strings | keys[] | select($tr[0][.] == null)' "$fresh")
if [[ -n "$missing" ]]; then
  print -u2 "localization gate: missing Turkish translations:"
  print -u2 -r -- "$missing"
  exit 1
fi

if ! diff -u \
  <(jq -r '.strings | keys[]' "$fresh" | sort) \
  <(jq -r '.strings | keys[]' "$catalog" | sort); then
  print -u2 "localization gate: checked-in String Catalog is stale"
  exit 1
fi

jq -e '.strings | all(.[]; .localizations.tr.stringUnit.state == "translated" and (.localizations.tr.stringUnit.value | length > 0))' "$catalog" >/dev/null
xcrun xcstringstool compile --output-directory "$temporary_directory/compiled" "$catalog"
print "localization gate: English source and Turkish translations are complete"
