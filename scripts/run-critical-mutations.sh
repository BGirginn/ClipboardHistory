#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
killed=0
survived=0
evidence_parent=${COREDECK_EVIDENCE_ROOT:-/private/tmp/coredeck-release-evidence}
mkdir -p "$evidence_parent"
evidence=$(mktemp -d "$evidence_parent/mutations.XXXXXX")
active_work=""
cleanup_work() {
  [[ -z "$active_work" ]] || rm -rf -- "$active_work"
}
trap cleanup_work EXIT
python3 "$repository_root/scripts/write-evidence-metadata.py" "$evidence/Environment.json" mutations
print "mutation gate: evidence=$evidence"

run_mutation() {
  local name=$1
  local selector=$2
  local mutation_root
  mutation_root="$evidence/$name"
  active_work=$(mktemp -d /private/tmp/coredeck-mutation-work.XXXXXX)
  local checkout="$active_work/repository"
  local log="$mutation_root/test.log"
  mkdir -p "$checkout" "$mutation_root"
  rsync -a --exclude=.git --exclude=.build "$repository_root/" "$checkout/"

  case "$name" in
    pasteboard_identity)
      perl -0pi -e 's/guard currentIdentity == identity else/guard currentIdentity != identity else/' "$checkout/CoreDeck/Services/Clipboard/ClipboardMonitor.swift"
      ;;
    retention_boundary)
      perl -0pi -e 's/if item\.creationDate < generalCutoff/if item.creationDate > generalCutoff/' "$checkout/CoreDeck/Services/Storage/StorageMaintenanceService.swift"
      ;;
    authenticated_decryption)
      perl -0pi -e 's/return try AES\.GCM\.open\(box, using: key\)/return box.ciphertext/' "$checkout/CoreDeck/Services/Security/SystemEncryptionCryptoBackend.swift"
      ;;
    search_conjunction)
      perl -0pi -e 's/terms\.allSatisfy \{ term in/terms.contains { term in/' "$checkout/CoreDeck/Models/ClipboardSearchQuery.swift"
      ;;
    archive_manifest)
      perl -0pi -e 's/archive\.itemHashes\[item\.id\.uuidString\.lowercased\(\)\] == \(try itemChecksum\(item\)\)/archive.itemHashes[item.id.uuidString.lowercased()] != (try itemChecksum(item))/' "$checkout/CoreDeck/Services/Storage/ExportImportService.swift"
      ;;
    open_storage_migration)
      perl -0pi -e 's/let shouldEncrypt = false/let shouldEncrypt = true/' "$checkout/CoreDeck/Services/Storage/StorageMaintenanceService.swift"
      ;;
  esac

  if diff -qr \
      "$repository_root/CoreDeck" \
      "$checkout/CoreDeck" >/dev/null; then
    print -u2 "mutation infrastructure failure: $name did not alter production source"
    exit 2
  fi
  diff -ru "$repository_root/CoreDeck" "$checkout/CoreDeck" \
    > "$mutation_root/Mutation.patch" || [[ $? == 1 ]]

  if xcodebuild -quiet \
      -project "$checkout/CoreDeck.xcodeproj" \
      -scheme CoreDeckTests \
      -configuration Debug \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$active_work/DerivedData" \
      -resultBundlePath "$mutation_root/Mutation.xcresult" \
      CODE_SIGNING_ALLOWED=NO \
      "-only-testing:$selector" test > "$log" 2>&1; then
    print -u2 "mutation survived: $name"
    (( survived += 1 ))
  else
    local summary
    summary=$(xcrun xcresulttool get test-results summary \
      --path "$mutation_root/Mutation.xcresult" 2>/dev/null) || summary='{}'
    print -r -- "$summary" > "$mutation_root/Summary.json"
    if jq -e --arg selector "${selector#CoreDeckTests/}" '
        .result == "Failed" and .failedTests > 0 and .skippedTests == 0
        and (.testFailures | length > 0)
        and all(.testFailures[];
          (.failureText | test("XCTAssert|XCTUnwrap|failed - "))
          and (.testIdentifierString | startswith($selector)))
      ' <<<"$summary" >/dev/null; then
      print "mutation killed: $name"
      (( killed += 1 ))
    else
      print -u2 "mutation infrastructure failure: $name"
      sed -n '1,120p' "$log" >&2
      exit 2
    fi
  fi
  cleanup_work
  active_work=""
}

run_mutation pasteboard_identity CoreDeckTests/ClipboardMonitorTests
run_mutation retention_boundary CoreDeckTests/AdvancedClipboardTests/testRetentionPreservesPinnedItemsAndDeletesAssets
run_mutation authenticated_decryption CoreDeckTests/PrivacySecurityTests/testAESGCMRoundTripAndTamperDetection
run_mutation search_conjunction CoreDeckTests/ClipboardSearchQueryTests/testFieldFiltersMatchProtectedAndPublicMetadata
run_mutation archive_manifest CoreDeckTests/AdvancedClipboardTests/testImportRejectsTamperedItemManifest
run_mutation open_storage_migration CoreDeckTests/PrivacySecurityTests/testLegacyEncryptedDatabaseItemMigratesToOpenStorage

print "mutation summary: killed=$killed survived=$survived"
(( survived == 0 ))
