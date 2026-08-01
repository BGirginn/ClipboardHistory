import AppKit
import Combine
import Foundation

@MainActor
protocol WorkspaceRevealing {
    func reveal(_ urls: [URL])
}

@MainActor
struct SystemWorkspaceRevealer: WorkspaceRevealing {
    private let revealAction: ([URL]) -> Void

    init(
        revealAction: @escaping ([URL]) -> Void = NSWorkspace.shared.activateFileViewerSelecting
    ) {
        self.revealAction = revealAction
    }

    func reveal(_ urls: [URL]) {
        revealAction(urls)
    }
}
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel {
    func selectNext() {
        moveSelection(by: 1)
    }

    func selectPrevious() {
        moveSelection(by: -1)
    }

    func restoreSelected() {
        guard let selectedItem else { return }
        restore(selectedItem)
    }

    func pasteSelectedToActiveApp() {
        guard let selectedItem else { return }
        paste(selectedItem)
    }

    func restoreVisibleItem(at index: Int) {
        let visible = pinnedItems + recentItems
        guard visible.indices.contains(index) else { return }
        selectedItemID = visible[index].id
        restore(visible[index])
    }

    func deleteSelected() {
        if selectedItemIDs.count > 1 {
            deleteSelectedItems()
        } else if let selectedItem {
            delete(selectedItem)
        }
    }

    func previewSelected() {
        guard let selectedItem,
              [.image, .imageGroup, .pdf, .files].contains(selectedItem.type) else { return }
        requestPreview?(selectedItem)
    }

    func closeOrClearSearch() {
        if !searchText.isEmpty {
            searchText = ""
        } else {
            requestClosePanel?()
        }
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func toggleIgnoreNextCopy() {
        if isIgnoringNextCopy {
            monitor.cancelIgnoringNextCopy()
            isIgnoringNextCopy = false
        } else {
            monitor.ignoreNextCopy()
            isIgnoringNextCopy = true
        }
    }

    func togglePrivateMode() {
        setPrivateModeEnabled(!isPrivateMode)
    }

    func setPrivateModeEnabled(_ enabled: Bool) {
        guard enabled != isPrivateMode || privateModeUntil != nil || pauseUntil != nil else { return }
        privateModeTask?.cancel()
        privateModeTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        isPrivateMode = enabled
        privateModeUntil = nil
        pauseUntil = nil
        privateModeDidChange?(enabled)
        Task { await thumbnailService.clearCache() }
    }

    func enablePrivateMode(minutes: Int) {
        privateModeTask?.cancel()
        pauseTask?.cancel()
        pauseTask = nil
        isPrivateMode = true
        let expiration = Date.now.addingTimeInterval(Double(minutes) * 60)
        privateModeUntil = expiration
        pauseUntil = nil
        privateModeDidChange?(true)
        privateModeTask = Task { [weak self] in
            do {
                try await self?.sleepClock.sleep(for: .seconds(minutes * 60))
                guard let self,
                      isPrivateMode,
                      privateModeUntil == expiration else { return }
                isPrivateMode = false
                privateModeUntil = nil
                privateModeTask = nil
                privateModeDidChange?(false)
            } catch {
                // A new privacy choice or app termination superseded this timer.
            }
        }
        Task { await thumbnailService.clearCache() }
    }

    func pauseRecording(minutes: Int) {
        privateModeTask?.cancel()
        privateModeTask = nil
        pauseTask?.cancel()
        isPrivateMode = false
        privateModeUntil = nil
        let expiration = Date.now.addingTimeInterval(Double(minutes) * 60)
        pauseUntil = expiration
        privateModeDidChange?(true)
        pauseTask = Task { [weak self] in
            do {
                try await self?.sleepClock.sleep(for: .seconds(minutes * 60))
                guard let self, pauseUntil == expiration else { return }
                pauseUntil = nil
                pauseTask = nil
                privateModeDidChange?(false)
            } catch {
                // A newer pause or app termination superseded this timer.
            }
        }
        Task { await thumbnailService.clearCache() }
    }

    func resumeRecording() {
        privateModeTask?.cancel()
        privateModeTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        isPrivateMode = false
        privateModeUntil = nil
        pauseUntil = nil
        privateModeDidChange?(false)
        Task { await thumbnailService.clearCache() }
    }

    func settingsDidChange() {
        guard !isShuttingDown else { return }
        refreshDisplayedItems()
        updateIgnoredPasteboardTypes()
        lockService.configure(
            enabled: settings.applicationLockEnabled,
            option: settings.autoLockOption
        )
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await thumbnailService.setCacheLimit(megabytes: settings.thumbnailCacheMegabytes)
            guard !Task.isCancelled else { return }
            if appliedEncryptionMode != settings.encryptionMode {
                await drainPendingItemWrites()
                guard !Task.isCancelled else { return }
                appliedEncryptionMode = settings.encryptionMode
                let persistent = items.filter { temporaryContent[$0.id] == nil }
                await storage.migrateEncryption(items: persistent, mode: settings.encryptionMode)
                let temporary = items.filter { temporaryContent[$0.id] != nil }
                items = temporary + (await storage.loadHistory())
                refreshDisplayedItems()
            }
            guard !Task.isCancelled else { return }
            await enforceUnpinnedHistoryLimit()
            guard !Task.isCancelled else { return }
            await runRetentionCleanup()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLoginRequested = enabled
        launchAtLoginService.setEnabled(enabled)
        settings.launchAtLoginRequested = launchAtLoginService.isEnabled
    }

    func refreshStorageInformation() async {
        storageMetrics = await storage.storageMetrics()
        migrationStatus = await storage.migrationStatus()
        launchAtLoginService.refresh()
        settings.launchAtLoginRequested = launchAtLoginService.isEnabled
    }

    func unlock() {
        Task { [weak self] in
            await self?.unlockAndWait()
        }
    }

    func unlockAndWait() async {
        await lockService.unlock()
        if !isLocked {
            presentNextSensitiveConfirmationIfUnlocked()
        }
    }

    func lock() {
        lockService.lock()
    }

    func setApplicationLockEnabled(_ enabled: Bool) {
        Task { [weak self] in
            await self?.setApplicationLockEnabledAndWait(enabled)
        }
    }

    @discardableResult
    func setApplicationLockEnabledAndWait(_ enabled: Bool) async -> Bool {
        guard enabled != settings.applicationLockEnabled else { return true }
        guard await lockService.authenticateAndSetEnabled(enabled) else {
            objectWillChange.send()
            return false
        }
        if enabled, settings.autoLockOption == .never {
            settings.autoLockOption = .whenMacLocks
        }
        settings.setApplicationLockEnabled(enabled)
        if !isLocked {
            presentNextSensitiveConfirmationIfUnlocked()
        }
        return true
    }

    func dismissError() {
        errorMessage = nil
    }

    func setGlobalShortcutError(_ message: String?) {
        globalShortcutError = message
    }

    func confirmSensitiveSave() {
        guard !isLocked,
              let id = pendingSensitiveItemIDs.first,
              let content = temporaryContent[id] else { return }
        removeTemporaryItem(id: id)
        presentNextSensitiveConfirmationIfUnlocked()
        Task { [weak self] in
            await self?.insertSensitivePermanently(content)
        }
    }

    func keepSensitiveTemporarily() {
        guard !isLocked, !pendingSensitiveItemIDs.isEmpty else { return }
        pendingSensitiveItemIDs.removeFirst()
        presentNextSensitiveConfirmationIfUnlocked()
    }

    func exportArchive(
        mode: ClipboardExportMode,
        includeImagesAndDocuments: Bool,
        includeFileReferences: Bool = true,
        password: String? = nil
    ) {
        Task { [weak self] in
            await self?.performArchiveExport(
                mode: mode,
                includeImagesAndDocuments: includeImagesAndDocuments,
                includeFileReferences: includeFileReferences,
                password: password
            )
        }
    }

    func importArchive(password: String? = nil) {
        Task { [weak self] in
            await self?.performArchiveImport(password: password)
        }
    }

    func importStorageRecoveryArchive(password: String) {
        Task { [weak self] in
            await self?.performStorageRecoveryImport(password: password)
        }
    }

    func runRetentionCleanup(prefetchedItems: [ClipboardItem]? = nil) async {
        await drainPendingItemWrites()
        let report = await storage.cleanup(
            historyLimit: settings.historyLimit,
            retentionDays: settings.retentionDays,
            imageRetentionDays: settings.imageRetentionDays,
            maximumStorageBytes: Int64(settings.maximumStorageMegabytes) * 1_024 * 1_024,
            prefetchedItems: prefetchedItems
        )
        if report.removedItemCount > 0 {
            cleanupMessage = String(localized: "Removed \(report.removedItemCount) items and reclaimed \(report.reclaimedBytes.formatted(.byteCount(style: .file))).")
            let temporaryItems = items.filter { temporaryContent[$0.id] != nil }
            items = temporaryItems + (await storage.loadHistory())
            let retainedIDs = Set(items.map(\.id))
            pasteboardIdentityByItemID = pasteboardIdentityByItemID.filter {
                retainedIDs.contains($0.key)
            }
            refreshDisplayedItems()
        }
    }

    func reveal(_ item: ClipboardItem) {
        if item.type == .files, let path = item.fileURLs.first {
            workspaceRevealer.reveal([URL(fileURLWithPath: path)])
            return
        }
        guard let filename = item.imageFilename ?? item.assetFilenames.first,
              let imageURL = storage.imageURL(
                  filename: filename,
                  isEncrypted: item.isEncrypted
              ) else { return }
        workspaceRevealer.reveal([
            imageURL
        ])
    }

    func exportImage(_ item: ClipboardItem, asJPEG: Bool) {
        Task { [weak self] in
            await self?.performImageExport(item, asJPEG: asJPEG)
        }
    }

}
