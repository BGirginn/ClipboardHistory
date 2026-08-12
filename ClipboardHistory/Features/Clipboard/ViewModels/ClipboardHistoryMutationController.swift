import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel {
    func insert(
        _ content: ClipboardContent,
        pasteboardIdentity: ClipboardPasteboardIdentity? = nil
    ) async {
        guard !isPaused else {
            AppLog.clipboard.debug("Clipboard capture skipped while recording is paused")
            return
        }
        guard !isLocked else {
            AppLog.clipboard.debug("Clipboard capture skipped while application lock is active")
            return
        }
        if let pasteboardIdentity,
           let expectedIdentity = lastProgrammaticallyWrittenIdentity {
            if pasteboardIdentity == expectedIdentity {
                associateExistingItem(hash: content.hash, with: pasteboardIdentity)
                lastProgrammaticallyWrittenHash = nil
                lastProgrammaticallyWrittenIdentity = nil
                AppLog.clipboard.debug("Programmatic clipboard restore ignored")
                return
            }
            if pasteboardIdentity.changeCount > expectedIdentity.changeCount {
                lastProgrammaticallyWrittenHash = nil
                lastProgrammaticallyWrittenIdentity = nil
            }
        } else if pasteboardIdentity == nil, let expectedHash = lastProgrammaticallyWrittenHash {
            lastProgrammaticallyWrittenHash = nil
            lastProgrammaticallyWrittenIdentity = nil
            if expectedHash == content.hash {
                AppLog.clipboard.debug("Programmatic clipboard restore ignored")
                return
            }
        }
        if let duplicate = duplicateItem(hash: content.hash) {
            if let pasteboardIdentity {
                pasteboardIdentityByItemID[duplicate.id] = pasteboardIdentity
            }
            AppLog.clipboard.debug("Clipboard duplicate ignored; scope=\(self.settings.duplicateDetectionScope.rawValue)")
            return
        }

        let analysis = await contentAnalyzer.analyze(
            content,
            recognizesImageText: settings.imageTextRecognitionEnabled
        )
        let sensitiveResult = sensitivityResult(for: content, analysis: analysis)
        let isTemporarySensitive = sensitiveResult.isSensitive
        let shouldEncrypt = false

        guard let item = await makeItem(
            from: content,
            sensitive: sensitiveResult.isSensitive,
            temporary: isTemporarySensitive,
            encrypted: shouldEncrypt,
            analysis: analysis
        ) else { return }

        if isTemporarySensitive {
            temporaryContent[item.id] = content
            scheduleExpiration(for: item)
            if settings.sensitiveStoragePolicy == .ask {
                pendingSensitiveItemIDs.append(item.id)
                presentNextSensitiveConfirmationIfUnlocked()
            }
        } else {
            do {
                try await storage.upsertThrowing(item)
            } catch {
                await storage.deleteImages(for: [item])
                errorMessage = String(localized: "Clipboard content could not be saved. Recording continues, but this item was not added.")
                return
            }
        }
        if let pasteboardIdentity {
            pasteboardIdentityByItemID[item.id] = pasteboardIdentity
        }
        items.insert(item, at: 0)
        await enforceUnpinnedHistoryLimit()
        refreshDisplayedItems()

        insertionsSinceCleanup += 1
        if insertionsSinceCleanup >= 20 {
            insertionsSinceCleanup = 0
            await runRetentionCleanup()
        }
    }

    func restore(_ item: ClipboardItem) {
        Task { [weak self] in
            await self?.restoreNow(item, representation: .original, directPaste: false)
        }
    }

    func restoreAndWait(_ item: ClipboardItem) async {
        await restoreNow(item, representation: .original, directPaste: false)
    }

    func copy(_ item: ClipboardItem, as representation: PasteRepresentation) {
        Task { [weak self] in
            await self?.restoreNow(item, representation: representation, directPaste: false)
        }
    }

    func paste(_ item: ClipboardItem, as representation: PasteRepresentation = .original) {
        Task { [weak self] in
            await self?.restoreNow(item, representation: representation, directPaste: true)
        }
    }

    func pasteAndWait(
        _ item: ClipboardItem,
        as representation: PasteRepresentation = .original
    ) async {
        await restoreNow(item, representation: representation, directPaste: true)
    }

    func capturePasteTargetApplication() {
        pasteService.captureTargetApplication()
    }

    func restoreStoredImage(filename: String, hash: String) async {
        let item = items.first { $0.imageFilename == filename && $0.hash == hash }
            ?? ClipboardItem(type: .image, imageFilename: filename, hash: hash)
        await restoreNow(item, representation: .original, directPaste: false)
    }

    func delete(_ item: ClipboardItem) {
        Task { [weak self] in
            await self?.finishDeleting(item)
        }
    }

    func deleteAndWait(_ item: ClipboardItem) async {
        await finishDeleting(item)
    }

    func removeFromHistory(_ item: ClipboardItem) {
        expirationTasks[item.id]?.cancel()
        expirationTasks[item.id] = nil
        temporaryContent[item.id] = nil
        pasteboardIdentityByItemID[item.id] = nil
        pasteStackItemIDs.removeAll { $0 == item.id }
        items.removeAll { $0.id == item.id }
        selectedItemIDs.remove(item.id)
        if detailItem?.id == item.id { detailItem = nil }
        refreshDisplayedItems()
    }

    func finishDeleting(_ item: ClipboardItem) async {
        await cancelAndAwaitPendingWrite(for: item.id)
        do {
            let outcome = try await storage.deleteItem(item)
            guard outcome.persistentChangeCommitted else { return }
            clearCurrentPasteboardIfNeeded(for: item)
            removeFromHistory(item)
            await thumbnailService.invalidate(itemID: item.id)
            if outcome.requiresCleanupRetry {
                cleanupMessage = String(localized: "The item was deleted, but residual file cleanup could not be completed. Cleanup will be retried.")
            }
        } catch {
            errorMessage = String(localized: "The clipboard item could not be deleted. Nothing was removed from history.")
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? .now : nil
        let updated = items[index]
        if temporaryContent[item.id] == nil {
            scheduleItemWrite(updated)
        }
        refreshDisplayedItems()
    }

    func selectOnly(_ item: ClipboardItem) {
        selectedItemID = item.id
        selectedItemIDs = [item.id]
    }

    func toggleSelection(_ item: ClipboardItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
            if selectedItemID == item.id { selectedItemID = selectedItemIDs.first }
        } else {
            selectedItemIDs.insert(item.id)
            selectedItemID = item.id
        }
    }

    func deleteSelectedItems() {
        let selection = selectedItems
        guard !selection.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for item in selection {
                await cancelAndAwaitPendingWrite(for: item.id)
            }
            do {
                let outcome = try await storage.deleteBatchThrowing(items: selection)
                guard outcome.persistentChangeCommitted else { return }
                for item in selection {
                    clearCurrentPasteboardIfNeeded(for: item)
                    removeFromHistory(item)
                    await thumbnailService.invalidate(itemID: item.id)
                }
                if outcome.requiresCleanupRetry {
                    cleanupMessage = String(localized: "The items were deleted, but residual file cleanup could not be completed. Cleanup will be retried.")
                }
            } catch {
                errorMessage = String(localized: "The clipboard items could not be deleted. Nothing was removed from history.")
            }
        }
    }

    func requestAgeCleanup(olderThan interval: TimeInterval) {
        pendingAgeCleanupInterval = interval
        isShowingAgeCleanupConfirmation = true
    }

    func confirmAgeCleanup() {
        guard let interval = pendingAgeCleanupInterval else { return }
        isShowingAgeCleanupConfirmation = false
        pendingAgeCleanupInterval = nil
        let cutoff = Date.now.addingTimeInterval(-interval)
        let targets = items.filter { !$0.isPinned && $0.creationDate < cutoff }
        Task { [weak self] in
            guard let self else { return }
            for item in targets {
                await deleteAndWait(item)
            }
        }
    }

    func addToPasteStack(_ item: ClipboardItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        pasteStackItemIDs.removeAll { $0 == item.id }
        pasteStackItemIDs.append(item.id)
        schedulePasteStackTimeout()
    }

    func removeFromPasteStack(_ item: ClipboardItem) {
        pasteStackItemIDs.removeAll { $0 == item.id }
        if pasteStackItemIDs.isEmpty {
            pasteStackTimeoutTask?.cancel()
            pasteStackTimeoutTask = nil
        }
    }

    func resetPasteStack() {
        pasteStackItemIDs.removeAll()
        pasteStackTimeoutTask?.cancel()
        pasteStackTimeoutTask = nil
    }

    func pasteNextStackItem() {
        Task { [weak self] in
            await self?.pasteNextStackItemAndWait()
        }
    }

    func pasteNextStackItemAndWait() async {
        let id: UUID?
        switch settings.pasteStackOrder {
        case .fifo:
            id = pasteStackItemIDs.first
        case .lifo:
            id = pasteStackItemIDs.last
        }
        guard let id, let item = items.first(where: { $0.id == id }) else { return }
        let completed = await restoreNow(item, representation: .original, directPaste: true)
        if completed, settings.pasteStackRemovesUsedItems {
            pasteStackItemIDs.removeAll { $0 == id }
        }
        if pasteStackItemIDs.isEmpty {
            pasteStackTimeoutTask?.cancel()
            pasteStackTimeoutTask = nil
        } else {
            schedulePasteStackTimeout()
        }
    }

    func updateItem(
        _ item: ClipboardItem,
        title: String,
        editedText: String?,
        tags: String,
        collectionID: UUID?,
        isSnippet: Bool
    ) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items[index]
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.displayTitle = normalizedTitle.isEmpty ? nil : normalizedTitle
        updated.protectedMetadata.displayTitle = updated.displayTitle
        updated.protectedMetadata.tags = Self.normalizedTags(from: tags)
        updated.collectionID = collectionID
        updated.isSnippet = isSnippet
        if isSnippet {
            updated.isPinned = true
            updated.pinnedAt = updated.pinnedAt ?? .now
        }
        if let editedText, [.text, .richText].contains(updated.type) {
            let visibleTextChanged = editedText != updated.text
            updated.text = editedText
            updated.hash = HashUtility.sha256(
                text: TextNormalizer.normalizedForHash(editedText)
            )
            updated.fileSize = Int64(editedText.utf8.count)
            if visibleTextChanged, updated.type == .richText {
                updated.type = .text
                updated.contentSubtype = .plainText
                updated.payloadFilename = nil
                updated.pasteboardTypes = [NSPasteboard.PasteboardType.string.rawValue]
            }
        }
        items[index] = updated
        if detailItem?.id == updated.id { detailItem = updated }
        if temporaryContent[updated.id] == nil {
            scheduleItemWrite(updated)
        }
        refreshDisplayedItems()
    }

    func toggleSnippet(_ item: ClipboardItem) {
        updateItem(
            item,
            title: item.displayTitle ?? "",
            editedText: item.text,
            tags: item.protectedMetadata.tags.joined(separator: ", "),
            collectionID: item.collectionID,
            isSnippet: !item.isSnippet
        )
    }

    func move(_ item: ClipboardItem, to collectionID: UUID?) {
        updateItem(
            item,
            title: item.displayTitle ?? "",
            editedText: item.text,
            tags: item.protectedMetadata.tags.joined(separator: ", "),
            collectionID: collectionID,
            isSnippet: item.isSnippet
        )
    }

    func createCollection(named proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        let collection = ClipboardCollection(
            name: name,
            sortOrder: (collections.map(\.sortOrder).max() ?? -1) + 1
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                try await storage.upsertCollection(collection)
                collections.append(collection)
                refreshDisplayedItems()
            } catch {
                errorMessage = String(localized: "Collection could not be saved.")
            }
        }
    }

    func deleteCollection(_ collection: ClipboardCollection) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await storage.deleteCollection(id: collection.id)
                collections.removeAll { $0.id == collection.id }
                for index in items.indices where items[index].collectionID == collection.id {
                    items[index].collectionID = nil
                }
                if detailItem?.collectionID == collection.id {
                    detailItem?.collectionID = nil
                }
                refreshDisplayedItems()
            } catch {
                errorMessage = String(localized: "Collection could not be deleted.")
            }
        }
    }

    func showDetails(_ item: ClipboardItem) {
        detailItem = item
    }

    func notifyMenuCommandDidRun() {
        menuCommandDidRun?()
    }

    func clearHistory() {
        isShowingClearConfirmation = true
    }

    func confirmClearHistory() {
        Task { [weak self] in
            await self?.clearHistoryNow()
        }
    }

    func clearHistoryNow() async {
        await cancelAndAwaitAllPendingWrites()
        do {
            let outcome = try await storage.clearAll()
            guard outcome.persistentChangeCommitted else { return }
            expirationTasks.values.forEach { $0.cancel() }
            expirationTasks.removeAll()
            temporaryContent.removeAll()
            items = []
            pinnedItems = []
            recentItems = []
            collections = []
            selectedItemID = nil
            selectedItemIDs.removeAll()
            detailItem = nil
            lastProgrammaticallyWrittenHash = nil
            lastProgrammaticallyWrittenIdentity = nil
            pasteboardIdentityByItemID.removeAll()
            resetPasteStack()
            await thumbnailService.clearCache()
            if outcome.requiresCleanupRetry {
                cleanupMessage = String(localized: "Clipboard history was deleted, but residual cleanup could not be completed. Cleanup will be retried.")
            }
        } catch {
            errorMessage = String(localized: "Clipboard history could not be cleared. Your saved history was preserved.")
        }
    }

}
