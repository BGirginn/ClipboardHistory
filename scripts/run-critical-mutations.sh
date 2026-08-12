#!/bin/zsh
set -euo pipefail

repository_root=${0:A:h:h}
killed=0
survived=0

run_mutation() {
  local name=$1
  local selector=$2
  local mutation_root
  mutation_root=$(mktemp -d "/private/tmp/clipboardhistory-mutation-${name}.XXXXXX")
  local checkout="$mutation_root/repository"
  local log="$mutation_root/test.log"
  mkdir -p "$checkout"
  rsync -a --exclude=.git --exclude=.build "$repository_root/" "$checkout/"

  case "$name" in
    pasteboard_identity)
      perl -0pi -e 's/guard currentIdentity == identity else/guard currentIdentity != identity else/' "$checkout/ClipboardHistory/Services/Clipboard/ClipboardMonitor.swift"
      ;;
    retention_boundary)
      perl -0pi -e 's/if item\.creationDate < generalCutoff/if item.creationDate > generalCutoff/' "$checkout/ClipboardHistory/Services/Storage/StorageMaintenanceService.swift"
      ;;
    authenticated_decryption)
      perl -0pi -e 's/return try AES\.GCM\.open\(box, using: key\)/return box.ciphertext/' "$checkout/ClipboardHistory/Services/Security/SystemEncryptionCryptoBackend.swift"
      ;;
    search_conjunction)
      perl -0pi -e 's/terms\.allSatisfy \{ term in/terms.contains { term in/' "$checkout/ClipboardHistory/Models/ClipboardSearchQuery.swift"
      ;;
    archive_manifest)
      perl -0pi -e 's/archive\.itemHashes\[item\.id\.uuidString\.lowercased\(\)\] == \(try itemChecksum\(item\)\)/archive.itemHashes[item.id.uuidString.lowercased()] != (try itemChecksum(item))/' "$checkout/ClipboardHistory/Services/Storage/ExportImportService.swift"
      ;;
    lock_capture)
      perl -0pi -e 's/guard !isLocked else/guard isLocked else/' "$checkout/ClipboardHistory/Features/Clipboard/ViewModels/ClipboardHistoryMutationController.swift"
      ;;
    open_storage_migration)
      perl -0pi -e 's/let shouldEncrypt = false/let shouldEncrypt = true/' "$checkout/ClipboardHistory/Services/Storage/StorageMaintenanceService.swift"
      ;;
  esac

  if diff -qr \
      "$repository_root/ClipboardHistory" \
      "$checkout/ClipboardHistory" >/dev/null; then
    print -u2 "mutation infrastructure failure: $name did not alter production source"
    rm -rf "$mutation_root"
    exit 2
  fi

  if xcodebuild -quiet \
      -project "$checkout/ClipboardHistory.xcodeproj" \
      -scheme ClipboardHistory \
      -configuration Debug \
      -destination 'platform=macOS,arch=arm64' \
      -derivedDataPath "$mutation_root/DerivedData" \
      CODE_SIGNING_ALLOWED=NO \
      "-only-testing:$selector" test > "$log" 2>&1; then
    print -u2 "mutation survived: $name"
    (( survived += 1 ))
  else
    if rg -q 'Test Case.*failed|Failing tests:|error:' "$log"; then
      print "mutation killed: $name"
      (( killed += 1 ))
    else
      print -u2 "mutation infrastructure failure: $name"
      sed -n '1,120p' "$log" >&2
      rm -rf "$mutation_root"
      exit 2
    fi
  fi
  rm -rf "$mutation_root"
}

run_mutation pasteboard_identity ClipboardHistoryTests/ClipboardMonitorTests
run_mutation retention_boundary ClipboardHistoryTests/AdvancedClipboardTests/testRetentionPreservesPinnedItemsAndDeletesAssets
run_mutation authenticated_decryption ClipboardHistoryTests/PrivacySecurityTests/testAESGCMRoundTripAndTamperDetection
run_mutation search_conjunction ClipboardHistoryTests/ClipboardSearchQueryTests/testFieldFiltersMatchProtectedAndPublicMetadata
run_mutation archive_manifest ClipboardHistoryTests/AdvancedClipboardTests/testImportRejectsTamperedItemManifest
run_mutation lock_capture ClipboardHistoryTests/ApplicationLockTests/testLockedCaptureIsAlwaysDroppedWithoutEncryption
run_mutation open_storage_migration ClipboardHistoryTests/PrivacySecurityTests/testLegacyEncryptedDatabaseItemMigratesToOpenStorage

print "mutation summary: killed=$killed survived=$survived"
(( survived == 0 ))
