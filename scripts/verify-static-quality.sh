#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
cd "$repository_root"

plutil -lint ClipboardHistory/Info.plist ClipboardHistory/ClipboardHistory.entitlements >/dev/null
plutil -lint ClipboardHistoryBrowserAudioBridge/Info.plist >/dev/null
xcodebuild -project ClipboardHistory.xcodeproj -list >/dev/null

if rg -n 'URLSession|NWConnection|Network\.framework|https?://' ClipboardHistory --glob '*.swift'; then
  print -u2 "static gate: production source contains a network API or URL literal"
  exit 1
fi
if rg -n '(^|[^A-Za-z])(try!|as!|fatalError|preconditionFailure)\b|\b(print|NSLog)\s*\(' ClipboardHistory --glob '*.swift'; then
  print -u2 "static gate: unsafe cast/error termination or console logging found"
  exit 1
fi
force_unwraps=$(rg -n '[A-Za-z0-9_\]\)]![\.\[,\)]|[A-Za-z0-9_\]\)]!\s*$' ClipboardHistory --glob '*.swift' \
  | rg -v 'Services/Presentation/QuickLookService\.swift:.*QLPreviewPanel!' || true)
if [[ -n "$force_unwraps" ]]; then
  print -r -- "$force_unwraps"
  print -u2 "static gate: production force unwrap found outside the Quick Look Objective-C signature allowlist"
  exit 1
fi
if rg -n 'DistributedNotificationCenter' ClipboardHistory ClipboardHistoryLoginItem ClipboardHistorySafariExtension ClipboardHistoryBrowserAudioBridge --glob '*.swift'; then
  print -u2 "static gate: unauthenticated distributed notification IPC found"
  exit 1
fi
unsafe_allowlist=scripts/unsafe-c-boundary-allowlist.txt
unsafe_files=$(rg -l 'unsafeBitCast|assumingMemoryBound|\bUnmanaged\b|nonisolated\(unsafe\)|baseAddress!' ClipboardHistory --glob '*.swift' | sort || true)
unexpected_unsafe=$(comm -23 <(print -r -- "$unsafe_files") <(sort "$unsafe_allowlist") || true)
if [[ -n "$unexpected_unsafe" ]]; then
  print -r -- "$unexpected_unsafe"
  print -u2 "static gate: unsafe C boundary is missing from scripts/unsafe-c-boundary-allowlist.txt"
  exit 1
fi
if rg -n 'clipboard.*privacy: \.public|text.*privacy: \.public|payload.*privacy: \.public' ClipboardHistory --glob '*.swift' -i; then
  print -u2 "static gate: potentially sensitive public log interpolation found"
  exit 1
fi

failed_structure=0
while IFS= read -r source; do
  line_count=$(wc -l <"$source" | tr -d ' ')
  if (( line_count > 500 )); then
    print -u2 "static gate: $source has $line_count lines; maximum is 500"
    failed_structure=1
  fi
  type_count=$(rg -c '^(private )?(final )?(struct|class|enum|actor|protocol) ' "$source" || true)
  if (( type_count > 1 )); then
    print -u2 "static gate: $source declares $type_count top-level types"
    failed_structure=1
  fi
done < <(rg --files ClipboardHistory -g '*.swift' | sort)
(( failed_structure == 0 )) || exit 1

scripts/verify-localizations.sh
print "static gate: plist, project, offline-only, logging, and source-structure checks passed"
