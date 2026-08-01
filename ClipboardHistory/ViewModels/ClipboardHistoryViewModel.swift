import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var recentItems: [ClipboardItem] = []
    @Published var collections: [ClipboardCollection] = []
    @Published var pasteStackItemIDs: [UUID] = []
    @Published var selectedItemID: UUID?
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var searchText = "" { didSet { refreshDisplayedItems() } }
    @Published var searchFocusRequest = 0
    @Published var isShowingSettings = false
    @Published var copiedItemID: UUID?
    @Published var detailItem: ClipboardItem?
    @Published var isPrivateMode: Bool
    @Published var privateModeUntil: Date?
    @Published var pauseUntil: Date?
    @Published var cleanupMessage: String?
    @Published var errorMessage: String?
    @Published var storageMetrics = StorageMetrics(
        databaseBytes: 0,
        imageBytes: 0,
        thumbnailBytes: 0,
        payloadBytes: 0
    )
    @Published var migrationStatus = String(localized: "Not checked")
    @Published var isShowingClearConfirmation = false
    @Published var isShowingAgeCleanupConfirmation = false
    @Published var pendingAgeCleanupInterval: TimeInterval?
    @Published var isShowingSensitiveSaveConfirmation = false
    @Published var archiveStatusMessage: String?
    @Published var globalShortcutError: String?
    @Published var isStorageAvailable = true

    let storage: StorageService
    var settings: AppSettings
    let launchAtLoginService: LaunchAtLoginService
    let lockService: AppLockService
    let thumbnailService: ThumbnailService
    let exportImportService: ExportImportService
    let archivePanelSelector: any ArchivePanelSelecting
    let storageRecoveryImporter: any StorageRecoveryImporting
    let workspaceRevealer: any WorkspaceRevealing

    var requestClosePanel: (() -> Void)?
    var requestPreview: ((ClipboardItem) -> Void)?
    var privateModeDidChange: ((Bool) -> Void)?
    var menuCommandDidRun: (() -> Void)?

    let monitor: ClipboardMonitor
    let clipboardWriter: any ClipboardWriting
    let pasteService: any ActiveApplicationPasting
    let dragProvider: any ClipboardDragProviding
    let secretDetector: SecretDetectionService
    let contentAnalyzer: any ClipboardContentAnalyzing
    let metadataExtractor: any ContentMetadataExtracting
    let sleepClock: any SleepClock
    var hasStarted = false
    var lastProgrammaticallyWrittenHash: String?
    var lastProgrammaticallyWrittenIdentity: ClipboardPasteboardIdentity?
    var pasteboardIdentityByItemID: [UUID: ClipboardPasteboardIdentity] = [:]
    var temporaryContent: [UUID: ClipboardContent] = [:]
    var expirationTasks: [UUID: Task<Void, Never>] = [:]
    var privateModeTask: Task<Void, Never>?
    var pauseTask: Task<Void, Never>?
    var pasteStackTimeoutTask: Task<Void, Never>?
    var copiedFeedbackTask: Task<Void, Never>?
    var panelCloseTask: Task<Void, Never>?
    var pendingItemWriteTasks: [UUID: Task<Void, Never>] = [:]
    var itemWriteGenerationByItemID: [UUID: Int] = [:]
    var maintenanceTask: Task<Void, Never>?
    var settingsCancellable: AnyCancellable?
    var lockCancellable: AnyCancellable?
    var insertionsSinceCleanup = 0
    var pendingSensitiveItemIDs: [UUID] = []
    var appliedEncryptionMode: EncryptionMode
    var isShuttingDown = false

    init(
        storage: StorageService = StorageService(),
        monitor: ClipboardMonitor = ClipboardMonitor(),
        restorePasteboard: NSPasteboard = .general,
        clipboardWriter: (any ClipboardWriting)? = nil,
        pasteService: any ActiveApplicationPasting = AccessibilityPasteService(),
        dragProvider: any ClipboardDragProviding = SystemClipboardDragProvider(),
        settings: AppSettings = AppSettings(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        lockService: AppLockService = AppLockService(),
        thumbnailService: ThumbnailService = .shared,
        exportImportService: ExportImportService = ExportImportService(),
        archivePanelSelector: any ArchivePanelSelecting = SystemArchivePanelSelector(),
        storageRecoveryImporter: any StorageRecoveryImporting = SystemStorageRecoveryImporter(),
        workspaceRevealer: any WorkspaceRevealing = SystemWorkspaceRevealer(),
        secretDetector: SecretDetectionService = SecretDetectionService(),
        contentAnalyzer: any ClipboardContentAnalyzing = ClipboardContentAnalysisService(),
        metadataExtractor: any ContentMetadataExtracting = ContentMetadataService(),
        sleepClock: any SleepClock = SystemSleepClock(),
        startsAutomatically: Bool = true
    ) {
        self.storage = storage
        self.monitor = monitor
        self.clipboardWriter = clipboardWriter ?? ClipboardPasteboardWriter(
            pasteboard: restorePasteboard
        )
        self.pasteService = pasteService
        self.dragProvider = dragProvider
        self.settings = settings
        self.launchAtLoginService = launchAtLoginService
        self.lockService = lockService
        self.thumbnailService = thumbnailService
        self.exportImportService = exportImportService
        self.archivePanelSelector = archivePanelSelector
        self.storageRecoveryImporter = storageRecoveryImporter
        self.workspaceRevealer = workspaceRevealer
        self.secretDetector = secretDetector
        self.contentAnalyzer = contentAnalyzer
        self.metadataExtractor = metadataExtractor
        self.sleepClock = sleepClock
        appliedEncryptionMode = settings.encryptionMode
        isPrivateMode = settings.privateModeDefaultEnabled
        monitor.delegate = self
        monitor.shouldCaptureFromApplication = { [weak self] bundleIdentifier in
            self?.shouldCapture(from: bundleIdentifier) ?? false
        }
        updateIgnoredPasteboardTypes()
        lockService.configure(
            enabled: settings.applicationLockEnabled,
            option: settings.autoLockOption,
            startsLocked: settings.applicationLockEnabled
        )
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

    var selectedItems: [ClipboardItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var pasteStackItems: [ClipboardItem] {
        pasteStackItemIDs.compactMap { id in items.first(where: { $0.id == id }) }
    }

    var isPaused: Bool {
        if isPrivateMode { return true }
        guard let pauseUntil else { return false }
        return pauseUntil > .now
    }

    var isLocked: Bool {
        lockService.isLocked
    }

    var isApplicationLockEnabled: Bool {
        lockService.isEnabled
    }

    func loadHistory() async {
        do {
            try await storage.verifyEncryptionAvailable()
            let persistentItems = try await storage.loadHistoryThrowing()
            collections = try await storage.loadCollectionsThrowing()
            items = persistentItems.filter { $0.expiresAt.map { $0 > .now } ?? true }
            isStorageAvailable = true
            refreshDisplayedItems()
            await runRetentionCleanup(prefetchedItems: persistentItems)
        } catch {
            isStorageAvailable = false
            stopMonitoring()
            errorMessage = String(localized: "Clipboard History cannot access its encryption key. Recording is stopped to protect your data. Restore Keychain access, then relaunch the app.")
            AppLog.storage.fault(
                "Storage unavailable; recording=stopped; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }

    func startMonitoring() {
        guard !hasStarted, isStorageAvailable else { return }
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
        panelCloseTask?.cancel()
        panelCloseTask = nil
        pendingItemWriteTasks.values.forEach { $0.cancel() }
        pendingItemWriteTasks.removeAll()
        itemWriteGenerationByItemID.removeAll()
        privateModeTask?.cancel()
        privateModeTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        pasteStackTimeoutTask?.cancel()
        pasteStackTimeoutTask = nil
        expirationTasks.values.forEach { $0.cancel() }
    }

    /// Completes the lifecycle boundary used by tests and controlled relaunches.
    /// Actor serialization ensures pending SQLite work has yielded before close.
    func shutdown() async {
        prepareForShutdown()
        await storage.close()
    }

}
