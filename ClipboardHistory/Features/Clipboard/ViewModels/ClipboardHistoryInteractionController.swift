import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel {
    @discardableResult
    func restoreNow(
        _ item: ClipboardItem,
        representation: PasteRepresentation,
        directPaste: Bool
    ) async -> Bool {
        guard await authorizeSensitiveAccess(to: item) else { return false }

        let succeeded: Bool
        if let temporary = temporaryContent[item.id] {
            succeeded = await clipboardWriter.write(
                content: temporary,
                representation: representation
            )
        } else {
            succeeded = await clipboardWriter.write(
                item: item,
                storage: storage,
                representation: representation
            )
        }
        guard succeeded else { return false }

        let identity = ClipboardPasteboardIdentity(changeCount: clipboardWriter.changeCount)
        pasteboardIdentityByItemID[item.id] = identity
        lastProgrammaticallyWrittenHash = item.hash
        lastProgrammaticallyWrittenIdentity = identity
        let updatedItem = markAsUsedImmediately(item)
        showCopiedFeedback(for: item.id)
        if let updatedItem, temporaryContent[item.id] == nil {
            scheduleItemWrite(updatedItem)
        }
        var completed = true
        if directPaste {
            switch await pasteService.paste() {
            case .pasted:
                break
            case .permissionRequired:
                completed = false
                errorMessage = String(localized: "Accessibility permission is required only for Paste to Active App. The item was copied; grant access in System Settings and try again.")
            case .targetUnavailable:
                completed = false
                errorMessage = String(localized: "The app that was active before Clipboard History opened is no longer available.")
            case .eventCreationFailed:
                completed = false
                errorMessage = String(localized: "Clipboard History could not create a paste keyboard event.")
            }
        }
        panelCloseTask?.cancel()
        panelCloseTask = nil
        if settings.closePanelAfterCopying {
            panelCloseTask = Task { [weak self] in
                try? await self?.sleepClock.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.requestClosePanel?()
            }
        }
        return completed
    }

    func markAsUsedImmediately(_ item: ClipboardItem) -> ClipboardItem? {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        items[index].lastUsedAt = .now
        items[index].useCount += 1
        let updated = items[index]
        if settings.selectedSortMode == .recentlyUsed, !updated.isPinned {
            refreshDisplayedItems()
        } else {
            if let pinnedIndex = pinnedItems.firstIndex(where: { $0.id == item.id }) {
                pinnedItems[pinnedIndex] = updated
            }
            if let recentIndex = recentItems.firstIndex(where: { $0.id == item.id }) {
                recentItems[recentIndex] = updated
            }
        }
        return updated
    }

    func scheduleItemWrite(_ item: ClipboardItem) {
        let previousWrite = pendingItemWriteTasks[item.id]
        let generation = (itemWriteGenerationByItemID[item.id] ?? 0) + 1
        itemWriteGenerationByItemID[item.id] = generation
        let task = Task { [weak self, storage] in
            if let previousWrite {
                await previousWrite.value
            }
            guard !Task.isCancelled else { return }
            do {
                try await storage.upsertThrowing(item)
                guard self?.itemWriteGenerationByItemID[item.id] == generation else { return }
                self?.pendingItemWriteFailureIDs.remove(item.id)
            } catch {
                self?.pendingItemWriteFailureIDs.insert(item.id)
                self?.errorMessage = String(localized: "A clipboard item change could not be saved.")
            }
        }
        pendingItemWriteTasks[item.id] = task
        Task { [weak self] in
            await task.value
            guard self?.itemWriteGenerationByItemID[item.id] == generation else { return }
            self?.pendingItemWriteTasks[item.id] = nil
            self?.itemWriteGenerationByItemID[item.id] = nil
        }
    }

    func cancelAndAwaitPendingWrite(for itemID: UUID) async {
        guard let pendingWrite = pendingItemWriteTasks[itemID] else { return }
        pendingWrite.cancel()
        await pendingWrite.value
        pendingItemWriteTasks[itemID] = nil
        itemWriteGenerationByItemID[itemID] = nil
        pendingItemWriteFailureIDs.remove(itemID)
    }

    func cancelAndAwaitAllPendingWrites() async {
        let pendingWrites = Array(pendingItemWriteTasks.values)
        pendingWrites.forEach { $0.cancel() }
        for pendingWrite in pendingWrites {
            await pendingWrite.value
        }
        pendingItemWriteTasks.removeAll()
        itemWriteGenerationByItemID.removeAll()
        pendingItemWriteFailureIDs.removeAll()
    }

    @discardableResult
    func drainPendingItemWrites() async -> Bool {
        let pendingWrites = Array(pendingItemWriteTasks.values)
        for pendingWrite in pendingWrites {
            await pendingWrite.value
        }
        return pendingItemWriteFailureIDs.isEmpty
    }

    func flushPendingWritesForShutdown() async -> Bool {
        stopMonitoring()
        let saved = await drainPendingItemWrites()
        if !saved {
            errorMessage = String(localized: "Clipboard changes could not be saved. Quit was cancelled so you can retry or remove the affected items.")
        }
        return saved
    }

    func showCopiedFeedback(for id: UUID) {
        copiedFeedbackTask?.cancel()
        copiedItemID = id
        copiedFeedbackTask = Task { [weak self] in
            try? await self?.sleepClock.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.copiedItemID = nil
        }
    }

    func schedulePasteStackTimeout() {
        pasteStackTimeoutTask?.cancel()
        let minutes = settings.pasteStackTimeoutMinutes
        guard minutes > 0, !pasteStackItemIDs.isEmpty else {
            pasteStackTimeoutTask = nil
            return
        }
        pasteStackTimeoutTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await sleepClock.sleep(for: .seconds(minutes * 60))
                guard !Task.isCancelled else { return }
                pasteStackItemIDs.removeAll()
                pasteStackTimeoutTask = nil
            } catch {
                // A stack change, reset, or app termination superseded this timeout.
            }
        }
    }

    func removeTemporaryItem(id: UUID) {
        expirationTasks[id]?.cancel()
        expirationTasks[id] = nil
        temporaryContent[id] = nil
        pasteboardIdentityByItemID[id] = nil
        pendingSensitiveItemIDs.removeAll { $0 == id }
        items.removeAll { $0.id == id }
        refreshDisplayedItems()
    }

    func presentNextSensitiveConfirmation() {
        pendingSensitiveItemIDs.removeAll { temporaryContent[$0] == nil }
        isShowingSensitiveSaveConfirmation = !pendingSensitiveItemIDs.isEmpty
    }

    func insertSensitivePermanently(_ content: ClipboardContent) async {
        guard let item = await makeItem(
            from: content,
            sensitive: true,
            temporary: false,
            encrypted: false,
            analysis: await contentAnalyzer.analyze(
                content,
                recognizesImageText: settings.imageTextRecognitionEnabled
            )
        ) else { return }
        do {
            try await storage.upsertThrowing(item)
        } catch {
            await storage.deleteImages(for: [item])
            errorMessage = String(localized: "Sensitive content could not be saved.")
            return
        }
        items.insert(item, at: 0)
        refreshDisplayedItems()
    }

}
