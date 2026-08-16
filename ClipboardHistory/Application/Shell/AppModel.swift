import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let router: AppRouter
    let clipboard: ClipboardHistoryViewModel
    let notes: NoteController
    let inputTools: InputToolsController
    let systemMetrics: SystemMetricsController
    let audioMixer: AudioMixerController
    let controlCenter: ControlCenterModel
    let settingsFeature: SettingsFeatureModel
    let settings: AppSettings

    init(
        storage: StorageService = StorageService(),
        monitor: ClipboardMonitor = ClipboardMonitor(),
        restorePasteboard: NSPasteboard = .general,
        clipboardWriter: (any ClipboardWriting)? = nil,
        pasteService: (any ActiveApplicationPasting)? = nil,
        dragProvider: any ClipboardDragProviding = SystemClipboardDragProvider(),
        settings: AppSettings = AppSettings(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        sensitiveContentAuthenticator: any SystemAuthenticating = LocalSystemAuthenticator(),
        thumbnailService: ThumbnailService = .shared,
        exportImportService: ExportImportService = ExportImportService(),
        archivePanelSelector: any ArchivePanelSelecting = SystemArchivePanelSelector(),
        storageRecoveryImporter: any StorageRecoveryImporting = SystemStorageRecoveryImporter(),
        workspaceRevealer: any WorkspaceRevealing = SystemWorkspaceRevealer(),
        secretDetector: SecretDetectionService = SecretDetectionService(),
        contentAnalyzer: any ClipboardContentAnalyzing = ClipboardContentAnalysisService(),
        metadataExtractor: any ContentMetadataExtracting = ContentMetadataService(),
        sleepClock: any SleepClock = SystemSleepClock(),
        inputEventTapCoordinator: (any InputEventTapCoordinating)? = nil,
        keyboardCleaningController: KeyboardCleaningController? = nil,
        scrollReversalController: ScrollReversalController? = nil,
        systemMetricsController: SystemMetricsController? = nil,
        audioMixerController: AudioMixerController? = nil,
        controlCenter: ControlCenterModel? = nil,
        router: AppRouter = AppRouter(),
        startsAutomatically: Bool = true
    ) {
        let accessibilityAuthorization = SystemAccessibilityAuthorization()
        let coordinator = inputEventTapCoordinator ?? SystemInputEventTapCoordinator(
            accessibilityAuthorization: accessibilityAuthorization
        )
        let pasteService = pasteService ?? AccessibilityPasteService(
            backend: SystemAccessibilityPasteBackend(
                accessibilityAuthorization: accessibilityAuthorization
            )
        )
        self.settings = settings
        self.router = router
        self.controlCenter = controlCenter ?? ControlCenterModel()
        systemMetrics = systemMetricsController ?? SystemMetricsController()
        audioMixer = audioMixerController ?? AudioMixerController()
        notes = NoteController(storage: storage)
        inputTools = InputToolsController(
            coordinator: coordinator,
            settings: settings,
            keyboardCleaning: keyboardCleaningController,
            scrollReversal: scrollReversalController
        )
        clipboard = ClipboardHistoryViewModel(
            storage: storage,
            monitor: monitor,
            restorePasteboard: restorePasteboard,
            clipboardWriter: clipboardWriter,
            pasteService: pasteService,
            dragProvider: dragProvider,
            settings: settings,
            launchAtLoginService: launchAtLoginService,
            sensitiveContentAuthenticator: sensitiveContentAuthenticator,
            thumbnailService: thumbnailService,
            exportImportService: exportImportService,
            archivePanelSelector: archivePanelSelector,
            storageRecoveryImporter: storageRecoveryImporter,
            workspaceRevealer: workspaceRevealer,
            secretDetector: secretDetector,
            contentAnalyzer: contentAnalyzer,
            metadataExtractor: metadataExtractor,
            sleepClock: sleepClock,
            startsAutomatically: startsAutomatically
        )
        settingsFeature = SettingsFeatureModel(
            clipboard: clipboard,
            controlCenter: self.controlCenter,
            notes: notes,
            inputTools: inputTools,
            systemMetrics: systemMetrics,
            audioMixer: audioMixer
        )
        clipboard.notesDidImport = { [weak notes] in
            await notes?.reload()
        }
    }

    func showControlCenter() {
        router.showControlCenter()
    }

    func showClipboard() {
        clipboard.prepareForPanelPresentation()
        router.showClipboard()
    }

    func showNoteList() {
        notes.showList()
        router.showNotes()
        Task { [weak notes] in
            await notes?.loadIfNeeded()
        }
    }

    func showQuickNote() {
        notes.openQuickEditor()
        router.showNotes()
    }

    func showKeyboardCleaning() {
        router.showKeyboardCleaning()
    }

    func showScrollReverse() {
        router.showScrollReverse()
    }

    func showSystemMonitor() {
        router.showSystemMonitor()
    }

    func showAudioMixer() {
        router.showAudioMixer()
    }

    func showMenuBarCustomization() {
        router.showMenuBarCustomization()
    }

    func openSettings(section: AppSettingsSection = .general) {
        router.openSettings(section: section)
    }

    func closeSettings() {
        router.closeSettings()
    }

    func requestLeaveNotes(
        to feature: AppFeature,
        settingsSection: AppSettingsSection? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            let outcome = await notes.flushPendingSave()
            guard outcome.allowsTransition else { return }
            switch feature {
            case .controlCenter:
                router.showControlCenter()
            case .clipboard:
                showClipboard()
            case .keyboardCleaning:
                router.showKeyboardCleaning()
            case .scrollReverse:
                router.showScrollReverse()
            case .systemMonitor:
                router.showSystemMonitor()
            case .audioMixer:
                router.showAudioMixer()
            case .menuBarCustomization:
                router.showMenuBarCustomization()
            case .settings:
                router.openSettings(section: settingsSection ?? .general)
            case .notes:
                router.showNotes()
            }
        }
    }

    func prepareForNormalPresentation() {
        router.showControlCenter()
    }

    func prepareForClipboardShortcut() {
        showClipboard()
    }

    func route(for id: UtilityFeatureID) -> AppFeature {
        switch id {
        case .clipboard: .clipboard
        case .notes: .notes
        case .keyboardCleaning: .keyboardCleaning
        case .scrollReverse: .scrollReverse
        case .systemMonitor: .systemMonitor
        case .audioMixer: .audioMixer
        }
    }

    func performStandaloneAction(
        for id: UtilityFeatureID,
        action overrideAction: FeatureClickAction? = nil
    ) -> AppFeature? {
        let action = overrideAction ?? controlCenter.configuration(for: id).clickAction
        switch (id, action) {
        case (_, .open):
            return route(for: id)
        case (.clipboard, .toggleClipboardRecording):
            clipboard.isPaused ? clipboard.resumeRecording() : clipboard.pauseRecording(minutes: 60)
            return nil
        case (.notes, .newNote):
            showQuickNote()
            return .notes
        case (.keyboardCleaning, .toggleKeyboardCleaning):
            if inputTools.keyboardCleaning.isActive {
                inputTools.keyboardCleaning.stop()
                return nil
            }
            inputTools.keyboardCleaning.start()
            return inputTools.keyboardCleaning.isActive ? nil : .keyboardCleaning
        case (.scrollReverse, .toggleScrollReverse):
            inputTools.scrollReversal.isEnabled.toggle()
            return inputTools.scrollReversal.isEnabled && !inputTools.scrollReversal.isActive
                ? .scrollReverse
                : nil
        case (.audioMixer, .muteAllAudio):
            audioMixer.toggleMuteAll()
            return nil
        default:
            return route(for: id)
        }
    }

    func prepareForShutdown() {
        inputTools.prepareForShutdown()
        systemMetrics.stop()
        audioMixer.stop()
        clipboard.prepareForShutdown()
    }

    @discardableResult
    func shutdown() async -> AppShutdownOutcome {
        inputTools.keyboardCleaning.stop()
        let noteOutcome = await notes.flushPendingSave()
        guard noteOutcome.allowsTransition else {
            router.showNotes()
            return AppShutdownOutcome(
                notes: noteOutcome,
                clipboard: .notAttempted,
                blockedFeature: .notes
            )
        }
        guard await clipboard.flushPendingWritesForShutdown() else {
            router.showClipboard()
            return AppShutdownOutcome(
                notes: noteOutcome,
                clipboard: .failed,
                blockedFeature: .clipboard
            )
        }
        prepareForShutdown()
        await clipboard.storage.close()
        return AppShutdownOutcome(
            notes: noteOutcome,
            clipboard: .saved,
            blockedFeature: nil
        )
    }
}
