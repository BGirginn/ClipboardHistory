import AppKit
import Combine
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var pinnedItems: [ClipboardItem] = []
    @Published private(set) var recentItems: [ClipboardItem] = []
    @Published var selectedItemID: UUID?
    @Published var searchText = "" { didSet { refreshDisplayedItems() } }
    @Published private(set) var searchFocusRequest = 0
    @Published var isShowingSettings = false
    @Published var copiedItemID: UUID?
    @Published var detailItem: ClipboardItem?
    @Published var isPrivateMode: Bool
    @Published private(set) var privateModeUntil: Date?
    @Published private(set) var pauseUntil: Date?
    @Published private(set) var cleanupMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var storageMetrics = StorageMetrics(
        databaseBytes: 0,
        imageBytes: 0,
        thumbnailBytes: 0,
        payloadBytes: 0
    )
    @Published private(set) var migrationStatus = "Not checked"
    @Published var isShowingClearConfirmation = false
    @Published var isShowingSensitiveSaveConfirmation = false
    @Published private(set) var archiveStatusMessage: String?
    @Published private(set) var globalShortcutError: String?

    let storage: StorageService
    var settings: AppSettings
    let launchAtLoginService: LaunchAtLoginService
    let lockService: AppLockService
    let thumbnailService: ThumbnailService
    let exportImportService: ExportImportService

    var requestClosePanel: (() -> Void)?
    var requestPreview: ((ClipboardItem) -> Void)?
    var privateModeDidChange: ((Bool) -> Void)?

    private let monitor: ClipboardMonitor
    private let restorePasteboard: NSPasteboard
    private let secretDetector: SecretDetectionService
    private var hasStarted = false
    private var lastProgrammaticallyWrittenHash: String?
    private var temporaryContent: [UUID: ClipboardContent] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]
    private var privateModeTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var copiedFeedbackTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var settingsCancellable: AnyCancellable?
    private var lockCancellable: AnyCancellable?
    private var insertionsSinceCleanup = 0
    private var pendingSensitiveItemID: UUID?
    private var appliedEncryptionMode: EncryptionMode
    private var isShuttingDown = false

    init(
        storage: StorageService = StorageService(),
        monitor: ClipboardMonitor = ClipboardMonitor(),
        restorePasteboard: NSPasteboard = .general,
        settings: AppSettings = AppSettings(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        lockService: AppLockService = AppLockService(),
        thumbnailService: ThumbnailService = .shared,
        exportImportService: ExportImportService = ExportImportService(),
        secretDetector: SecretDetectionService = SecretDetectionService(),
        startsAutomatically: Bool = true
    ) {
        self.storage = storage
        self.monitor = monitor
        self.restorePasteboard = restorePasteboard
        self.settings = settings
        self.launchAtLoginService = launchAtLoginService
        self.lockService = lockService
        self.thumbnailService = thumbnailService
        self.exportImportService = exportImportService
        self.secretDetector = secretDetector
        appliedEncryptionMode = settings.encryptionMode
        isPrivateMode = settings.privateModeDefaultEnabled
        monitor.delegate = self
        monitor.shouldCaptureFromApplication = { [weak self] bundleIdentifier in
            self?.shouldCapture(from: bundleIdentifier) ?? false
        }
        lockService.configure(option: settings.autoLockOption)
        observeSharedState()

        if startsAutomatically {
            Task { [weak self] in
                await self?.loadHistoryAndStartMonitoring()
            }
        }
    }

    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return (pinnedItems + recentItems).first { $0.id == selectedItemID }
    }

    var isPaused: Bool {
        if isPrivateMode { return true }
        guard let pauseUntil else { return false }
        return pauseUntil > .now
    }

    var isLocked: Bool {
        lockService.isLocked
    }

    func loadHistory() async {
        let persistentItems = await storage.loadHistory()
        items = persistentItems.filter { $0.expiresAt.map { $0 > .now } ?? true }
        refreshDisplayedItems()
        await runRetentionCleanup()
    }

    func startMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.start()
    }

    func stopMonitoring() {
        guard hasStarted else { return }
        hasStarted = false
        monitor.stop()
    }

    func prepareForShutdown() {
        isShuttingDown = true
        stopMonitoring()
        settingsCancellable = nil
        lockCancellable = nil
        maintenanceTask?.cancel()
        maintenanceTask = nil
        copiedFeedbackTask?.cancel()
        privateModeTask?.cancel()
        privateModeTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        expirationTasks.values.forEach { $0.cancel() }
    }

    func insert(_ content: ClipboardContent) async {
        guard !isPaused else {
            AppLog.clipboard.debug("Clipboard capture skipped while recording is paused")
            return
        }
        if let expectedHash = lastProgrammaticallyWrittenHash {
            lastProgrammaticallyWrittenHash = nil
            if expectedHash == content.hash {
                AppLog.clipboard.debug("Programmatic clipboard restore ignored")
                return
            }
        }
        guard !isDuplicate(hash: content.hash) else {
            AppLog.clipboard.debug("Clipboard duplicate ignored; scope=\(self.settings.duplicateDetectionScope.rawValue)")
            return
        }

        let sensitiveResult = sensitivityResult(for: content)
        let isTemporarySensitive = sensitiveResult.isSensitive
            && settings.sensitiveStoragePolicy != .encrypted
        let shouldEncrypt = settings.encryptionMode == .all
            || (sensitiveResult.isSensitive && settings.encryptionMode == .sensitive)
            || (sensitiveResult.isSensitive && settings.sensitiveStoragePolicy == .encrypted)

        guard let item = await makeItem(
            from: content,
            sensitive: sensitiveResult.isSensitive,
            temporary: isTemporarySensitive,
            encrypted: shouldEncrypt
        ) else { return }

        if isTemporarySensitive {
            temporaryContent[item.id] = content
            scheduleExpiration(for: item)
            if settings.sensitiveStoragePolicy == .ask {
                pendingSensitiveItemID = item.id
                isShowingSensitiveSaveConfirmation = true
            }
        } else {
            await storage.upsert(item)
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
            await self?.restoreNow(item)
        }
    }

    func restoreAndWait(_ item: ClipboardItem) async {
        await restoreNow(item)
    }

    func restoreStoredImage(filename: String, hash: String) async {
        let item = items.first { $0.imageFilename == filename && $0.hash == hash }
            ?? ClipboardItem(type: .image, imageFilename: filename, hash: hash)
        await restoreNow(item)
    }

    func delete(_ item: ClipboardItem) {
        expirationTasks[item.id]?.cancel()
        expirationTasks[item.id] = nil
        temporaryContent[item.id] = nil
        items.removeAll { $0.id == item.id }
        Task { [storage, thumbnailService] in
            await storage.deleteItem(item)
            await thumbnailService.invalidate(itemID: item.id)
        }
        if detailItem?.id == item.id { detailItem = nil }
        refreshDisplayedItems()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items[index].pinnedAt = items[index].isPinned ? .now : nil
        let updated = items[index]
        if temporaryContent[item.id] == nil {
            Task { await storage.upsert(updated) }
        }
        refreshDisplayedItems()
    }

    func showDetails(_ item: ClipboardItem) {
        detailItem = item
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
        expirationTasks.values.forEach { $0.cancel() }
        expirationTasks.removeAll()
        temporaryContent.removeAll()
        items = []
        pinnedItems = []
        recentItems = []
        selectedItemID = nil
        detailItem = nil
        lastProgrammaticallyWrittenHash = nil
        await thumbnailService.clearCache()
        await storage.clearAll()
    }

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

    func deleteSelected() {
        guard let selectedItem else { return }
        delete(selectedItem)
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
                try await Task.sleep(for: .seconds(minutes * 60))
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
                try await Task.sleep(for: .seconds(minutes * 60))
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
        lockService.configure(option: settings.autoLockOption)
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            guard let self else { return }
            await thumbnailService.setCacheLimit(megabytes: settings.thumbnailCacheMegabytes)
            guard !Task.isCancelled else { return }
            if appliedEncryptionMode != settings.encryptionMode {
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
            await self?.lockService.unlock()
        }
    }

    func lock() {
        lockService.lock()
    }

    func dismissError() {
        errorMessage = nil
    }

    func setGlobalShortcutError(_ message: String?) {
        globalShortcutError = message
    }

    func confirmSensitiveSave() {
        guard let id = pendingSensitiveItemID,
              let content = temporaryContent[id] else { return }
        removeTemporaryItem(id: id)
        isShowingSensitiveSaveConfirmation = false
        pendingSensitiveItemID = nil
        Task { [weak self] in
            await self?.insertSensitivePermanently(content)
        }
    }

    func keepSensitiveTemporarily() {
        pendingSensitiveItemID = nil
        isShowingSensitiveSaveConfirmation = false
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

    func runRetentionCleanup() async {
        let report = await storage.cleanup(
            historyLimit: settings.historyLimit,
            retentionDays: settings.retentionDays,
            imageRetentionDays: settings.imageRetentionDays,
            maximumStorageBytes: Int64(settings.maximumStorageMegabytes) * 1_024 * 1_024
        )
        if report.removedItemCount > 0 {
            cleanupMessage = "Removed \(report.removedItemCount) items and reclaimed \(report.reclaimedBytes.formatted(.byteCount(style: .file)))."
            let temporaryItems = items.filter { temporaryContent[$0.id] != nil }
            items = temporaryItems + (await storage.loadHistory())
            refreshDisplayedItems()
        }
    }

    func reveal(_ item: ClipboardItem) {
        if item.type == .files, let path = item.fileURLs.first {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        guard let filename = item.imageFilename ?? item.assetFilenames.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            storage.imageURL(filename: filename, isEncrypted: item.isEncrypted)
        ])
    }

    func exportImage(_ item: ClipboardItem, asJPEG: Bool) {
        Task { [weak self] in
            await self?.performImageExport(item, asJPEG: asJPEG)
        }
    }

    private func loadHistoryAndStartMonitoring() async {
        await loadHistory()
        startMonitoring()
        AppLog.lifecycle.notice("Clipboard history ready; persistedCount=\(self.items.count)")
    }

    private func observeSharedState() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                guard self?.isShuttingDown == false else { return }
                self?.settingsDidChange()
            }
        }
        lockCancellable = lockService.$isLocked.dropFirst().sink { [weak self] isLocked in
            self?.objectWillChange.send()
            if isLocked {
                Task { await self?.thumbnailService.clearCache() }
            }
        }
    }

    func shouldCapture(from bundleIdentifier: String?) -> Bool {
        guard !isPaused, !lockService.isLocked else { return false }
        guard let bundle = bundleIdentifier?.lowercased() else { return true }
        if settings.allowedBundleIdentifiers.contains(bundle) { return true }
        return !settings.excludedBundleIdentifiers.contains(bundle)
    }

    private func sensitivityResult(for content: ClipboardContent) -> SecretDetectionResult {
        guard settings.secretDetectionEnabled,
              case let .text(value, _, _, _, _, source) = content else {
            return SecretDetectionResult(isSensitive: false, confidence: 0, signals: [])
        }
        return secretDetector.detect(in: value, sourceBundleIdentifier: source)
    }

    private func makeItem(
        from content: ClipboardContent,
        sensitive: Bool,
        temporary: Bool,
        encrypted: Bool
    ) async -> ClipboardItem? {
        let id = UUID()
        let expiresAt = temporary
            ? Date.now.addingTimeInterval(Double(settings.sensitiveRetentionSeconds))
            : nil

        switch content {
        case let .text(value, rtfData, htmlData, subtype, hash, source):
            var payloadFilename: String?
            var itemType: ClipboardItemType = .text
            if !temporary, (htmlData != nil || rtfData != nil), settings.captureRichText {
                let payload = RichTextPayload(rtfData: rtfData, htmlData: htmlData)
                guard let payloadData = try? JSONEncoder().encode(payload) else { return nil }
                payloadFilename = await storage.storePayload(
                    payloadData,
                    id: id,
                    extension: "rich",
                    encrypt: encrypted
                )
                itemType = .richText
            }
            return ClipboardItem(
                id: id,
                type: itemType,
                text: value,
                hash: hash,
                displayTitle: value.split(separator: "\n", maxSplits: 1).first.map(String.init),
                contentSubtype: subtype,
                expiresAt: expiresAt,
                isSensitive: sensitive,
                sourceApplicationBundleID: source,
                payloadFilename: payloadFilename,
                fileSize: Int64(value.utf8.count + (rtfData?.count ?? 0) + (htmlData?.count ?? 0)),
                isEncrypted: encrypted
            )

        case let .images(pngData, hash, source):
            guard !temporary else { return nil }
            let dimensions = await Task.detached(priority: .utility) {
                pngData.first.flatMap(ImageMetadataUtility.dimensions)
            }.value
            var filenames: [String] = []
            for (index, data) in pngData.enumerated() {
                guard let filename = await storage.storeImage(
                    data,
                    id: id,
                    encrypt: encrypted,
                    index: pngData.count == 1 ? nil : index
                ) else {
                    let partial = ClipboardItem(
                        id: id,
                        type: .imageGroup,
                        hash: hash,
                        assetFilenames: filenames,
                        isEncrypted: encrypted
                    )
                    await storage.deleteImages(for: [partial])
                    return nil
                }
                filenames.append(filename)
            }
            let thumbnailFilename = "\(id.uuidString.lowercased())-thumb.png"
            let isGroup = pngData.count > 1
            return ClipboardItem(
                id: id,
                type: isGroup ? .imageGroup : .image,
                imageFilename: isGroup ? nil : filenames.first,
                hash: hash,
                displayTitle: isGroup ? "\(pngData.count) Images" : "Image",
                thumbnailFilename: thumbnailFilename,
                contentSubtype: isGroup ? .imageGroup : .image,
                isSensitive: sensitive,
                sourceApplicationBundleID: source,
                assetFilenames: isGroup ? filenames : [],
                imageWidth: dimensions?.width,
                imageHeight: dimensions?.height,
                fileSize: Int64(pngData.reduce(0) { $0 + $1.count }),
                isEncrypted: encrypted
            )

        case let .pdf(data, hash, source):
            guard settings.capturePDFs,
                  !temporary,
                  let filename = await storage.storePayload(
                      data,
                      id: id,
                      extension: "pdf",
                      encrypt: encrypted
                  ) else { return nil }
            let pageCount = await Task.detached(priority: .utility) {
                PDFDocument(data: data)?.pageCount
            }.value
            return ClipboardItem(
                id: id,
                type: .pdf,
                hash: hash,
                displayTitle: "PDF Document",
                thumbnailFilename: "\(id.uuidString.lowercased())-thumb.png",
                contentSubtype: .pdf,
                isSensitive: sensitive,
                sourceApplicationBundleID: source,
                payloadFilename: filename,
                pageCount: pageCount,
                fileSize: Int64(data.count),
                isEncrypted: encrypted
            )

        case let .files(urls, bookmarks, hash, source):
            guard settings.captureFiles, !temporary else { return nil }
            let firstName = urls.first?.lastPathComponent ?? "Files"
            return ClipboardItem(
                id: id,
                type: .files,
                hash: hash,
                displayTitle: urls.count == 1 ? firstName : "\(firstName) and \(urls.count - 1) more",
                contentSubtype: urls.count == 1 ? .file : .files,
                isSensitive: sensitive,
                sourceApplicationBundleID: source,
                fileURLs: urls.map(\.path),
                fileBookmarks: bookmarks,
                fileSize: urls.reduce(Int64(0)) { result, url in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return result + Int64(size)
                },
                isEncrypted: encrypted
            )
        }
    }

    private func isDuplicate(hash: String) -> Bool {
        switch settings.duplicateDetectionScope {
        case .newest:
            return items.first?.hash == hash
        case .lastTen:
            return items.prefix(10).contains { $0.hash == hash }
        case .lastHour:
            let cutoff = Date.now.addingTimeInterval(-3_600)
            return items.contains { $0.creationDate >= cutoff && $0.hash == hash }
        case .fullHistory:
            return items.contains { $0.hash == hash }
        }
    }

    private func scheduleExpiration(for item: ClipboardItem) {
        guard let expiresAt = item.expiresAt else { return }
        expirationTasks[item.id]?.cancel()
        expirationTasks[item.id] = Task { [weak self] in
            let seconds = max(0, expiresAt.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                temporaryContent[item.id] = nil
                items.removeAll { $0.id == item.id }
                expirationTasks[item.id] = nil
                refreshDisplayedItems()
            } catch {
                // Cancellation means the item was removed or the app is terminating.
            }
        }
    }

    private func enforceUnpinnedHistoryLimit() async {
        let unpinned = items.filter { !$0.isPinned && temporaryContent[$0.id] == nil }
            .sorted { $0.creationDate > $1.creationDate }
        guard unpinned.count > settings.historyLimit else { return }
        for item in unpinned.dropFirst(settings.historyLimit) {
            items.removeAll { $0.id == item.id }
            await storage.deleteItem(item)
            await thumbnailService.invalidate(itemID: item.id)
        }
    }

    private func refreshDisplayedItems() {
        var filtered = items.filter(matchesSearch)
        switch settings.selectedFilter {
        case .all:
            break
        case .text:
            filtered = filtered.filter { $0.type == .text || $0.type == .richText }
        case .images:
            filtered = filtered.filter { $0.type == .image || $0.type == .imageGroup }
        case .pinned:
            filtered = filtered.filter(\.isPinned)
        }

        pinnedItems = filtered.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
        let unpinned = filtered.filter { !$0.isPinned }
        switch settings.selectedSortMode {
        case .newestFirst:
            recentItems = unpinned.sorted { $0.creationDate > $1.creationDate }
        case .oldestFirst:
            recentItems = unpinned.sorted { $0.creationDate < $1.creationDate }
        case .recentlyUsed:
            recentItems = unpinned.sorted {
                ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
            }
        }

        let visibleIDs = Set((pinnedItems + recentItems).map(\.id))
        if selectedItemID.map({ !visibleIDs.contains($0) }) ?? true {
            selectedItemID = (pinnedItems + recentItems).first?.id
        }
    }

    private func matchesSearch(_ item: ClipboardItem) -> Bool {
        let tokens = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        guard !item.isSensitive else { return false }
        let metadata: String
        switch item.type {
        case .text, .richText:
            metadata = [item.text, item.displayTitle, item.contentSubtype.rawValue]
                .compactMap { $0 }.joined(separator: " ")
        case .image, .imageGroup, .pdf, .files:
            metadata = [item.displayTitle, item.contentSubtype.rawValue]
                .compactMap { $0 }.joined(separator: " ")
        }
        return tokens.allSatisfy(metadata.localizedStandardContains)
    }

    private func moveSelection(by offset: Int) {
        let visible = pinnedItems + recentItems
        guard !visible.isEmpty else {
            selectedItemID = nil
            return
        }
        guard let selectedItemID,
              let currentIndex = visible.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = visible.first?.id
            return
        }
        let newIndex = min(max(0, currentIndex + offset), visible.count - 1)
        self.selectedItemID = visible[newIndex].id
    }

    private func restoreNow(_ item: ClipboardItem) async {
        guard !lockService.isLocked else {
            errorMessage = "Unlock Clipboard History before restoring an item."
            return
        }

        let succeeded: Bool
        if let temporary = temporaryContent[item.id] {
            succeeded = await write(content: temporary)
        } else {
            succeeded = await write(item: item)
        }
        guard succeeded else { return }

        lastProgrammaticallyWrittenHash = item.hash
        await markAsUsed(item)
        showCopiedFeedback(for: item.id)
        if settings.closePanelAfterCopying {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.requestClosePanel?()
            }
        }
    }

    private func write(content: ClipboardContent) async -> Bool {
        switch content {
        case let .text(value, rtfData, htmlData, _, _, _):
            return writeText(value, rtfData: rtfData, htmlData: htmlData)
        case let .images(pngData, _, _):
            return writeImages(pngData)
        case let .pdf(data, _, _):
            return writePDF(data)
        case let .files(urls, _, _, _):
            return writeFiles(urls)
        }
    }

    private func write(item: ClipboardItem) async -> Bool {
        switch item.type {
        case .text:
            guard let text = item.text else { return false }
            return writeText(text, rtfData: nil, htmlData: nil)

        case .richText:
            guard let text = item.text else { return false }
            var rtfData: Data?
            var htmlData: Data?
            if let filename = item.payloadFilename,
               let data = await storage.payloadData(filename: filename, isEncrypted: item.isEncrypted) {
                if let payload = try? JSONDecoder().decode(RichTextPayload.self, from: data) {
                    rtfData = payload.rtfData
                    htmlData = payload.htmlData
                } else if filename.hasSuffix(".html") {
                    htmlData = data
                } else {
                    rtfData = data
                }
            }
            return writeText(text, rtfData: rtfData, htmlData: htmlData)

        case .image:
            guard let filename = item.imageFilename,
                  let data = await storage.imageData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return false }
            return writeImages([data])

        case .imageGroup:
            var images: [Data] = []
            for filename in item.assetFilenames {
                if let data = await storage.imageData(
                    filename: filename,
                    isEncrypted: item.isEncrypted
                ) {
                    images.append(data)
                }
            }
            return images.count == item.assetFilenames.count && writeImages(images)

        case .pdf:
            guard let filename = item.payloadFilename,
                  let data = await storage.payloadData(
                      filename: filename,
                      isEncrypted: item.isEncrypted
                  ) else { return false }
            return writePDF(data)

        case .files:
            return writeFiles(resolveFileURLs(for: item))
        }
    }

    private func writeText(_ text: String, rtfData: Data?, htmlData: Data?) -> Bool {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(text, forType: .string)
        if let rtfData { pasteboardItem.setData(rtfData, forType: .rtf) }
        if let htmlData { pasteboardItem.setData(htmlData, forType: .html) }
        restorePasteboard.clearContents()
        return restorePasteboard.writeObjects([pasteboardItem])
    }

    private func writeImages(_ pngData: [Data]) -> Bool {
        let objects = pngData.compactMap { data -> NSPasteboardItem? in
            guard let image = NSImage(data: data), let tiff = image.tiffRepresentation else { return nil }
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            item.setData(tiff, forType: .tiff)
            return item
        }
        guard objects.count == pngData.count else { return false }
        restorePasteboard.clearContents()
        return restorePasteboard.writeObjects(objects)
    }

    private func writePDF(_ data: Data) -> Bool {
        let item = NSPasteboardItem()
        item.setData(data, forType: .pdf)
        restorePasteboard.clearContents()
        return restorePasteboard.writeObjects([item])
    }

    private func writeFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        restorePasteboard.clearContents()
        return restorePasteboard.writeObjects(urls as [NSURL])
    }

    private func resolveFileURLs(for item: ClipboardItem) -> [URL] {
        var resolved: [URL] = []
        for bookmark in item.fileBookmarks {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                resolved.append(url)
            }
        }
        if resolved.isEmpty {
            resolved = item.fileURLs.map { URL(fileURLWithPath: $0) }
        }
        return resolved.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func markAsUsed(_ item: ClipboardItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastUsedAt = .now
        items[index].useCount += 1
        let updated = items[index]
        if temporaryContent[item.id] == nil {
            await storage.upsert(updated)
        }
        refreshDisplayedItems()
    }

    private func showCopiedFeedback(for id: UUID) {
        copiedFeedbackTask?.cancel()
        copiedItemID = id
        copiedFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.copiedItemID = nil
        }
    }

    private func removeTemporaryItem(id: UUID) {
        expirationTasks[id]?.cancel()
        expirationTasks[id] = nil
        temporaryContent[id] = nil
        items.removeAll { $0.id == id }
        refreshDisplayedItems()
    }

    private func insertSensitivePermanently(_ content: ClipboardContent) async {
        guard let item = await makeItem(
            from: content,
            sensitive: true,
            temporary: false,
            encrypted: true
        ) else { return }
        await storage.upsert(item)
        items.insert(item, at: 0)
        refreshDisplayedItems()
    }

    private func performImageExport(_ item: ClipboardItem, asJPEG: Bool) async {
        guard let filename = item.imageFilename ?? item.assetFilenames.first,
              let pngData = await storage.imageData(
                  filename: filename,
                  isEncrypted: item.isEncrypted
              ) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = asJPEG ? "Clipboard Image.jpg" : "Clipboard Image.png"
        panel.allowedContentTypes = asJPEG ? [.jpeg] : [.png]
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        do {
            let output = asJPEG ? try jpegData(from: pngData) : pngData
            try output.write(to: destination, options: .atomic)
        } catch {
            errorMessage = "Image export failed: \(error.localizedDescription)"
        }
    }

    private func performArchiveExport(
        mode: ClipboardExportMode,
        includeImagesAndDocuments: Bool,
        includeFileReferences: Bool,
        password: String?
    ) async {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = mode == .encrypted
            ? "ClipboardHistory-Encrypted.clipboardarchive"
            : "ClipboardHistory.clipboardarchive"
        panel.allowedContentTypes = [.data]
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        do {
            try await exportImportService.exportArchive(
                items: items,
                storage: storage,
                to: destination,
                mode: mode,
                includeImagesAndDocuments: includeImagesAndDocuments,
                includeFileReferences: includeFileReferences,
                password: password
            )
            archiveStatusMessage = "Export completed."
        } catch {
            archiveStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func performArchiveImport(password: String?) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        guard await panel.begin() == .OK, let source = panel.url else { return }
        do {
            let report = try await exportImportService.importArchive(
                from: source,
                password: password,
                storage: storage,
                existingItems: items,
                encryptionMode: settings.encryptionMode
            )
            let temporary = items.filter { temporaryContent[$0.id] != nil }
            items = temporary + (await storage.loadHistory())
            refreshDisplayedItems()
            archiveStatusMessage = "Imported \(report.importedCount); skipped \(report.duplicateCount) duplicates."
        } catch {
            archiveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func jpegData(from pngData: Data) throws -> Data {
        guard let source = NSImage(data: pngData) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let composited = NSImage(size: source.size)
        composited.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: source.size).fill()
        source.draw(in: NSRect(origin: .zero, size: source.size))
        composited.unlockFocus()
        guard let tiff = composited.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return jpeg
    }
}

extension ClipboardHistoryViewModel: ClipboardMonitorDelegate {
    func clipboardMonitor(_ monitor: ClipboardMonitor, didReceive content: ClipboardContent) {
        Task { [weak self] in
            await self?.insert(content)
        }
    }
}
