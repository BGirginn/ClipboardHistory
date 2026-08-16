import Combine
import Foundation

@MainActor
final class SettingsFeatureModel: ObservableObject {
    let clipboard: ClipboardHistoryViewModel
    var settings: AppSettings
    let launchAtLoginService: LaunchAtLoginService
    let controlCenter: ControlCenterModel
    let notes: NoteController
    let inputTools: InputToolsController
    let systemMetrics: SystemMetricsController
    let audioMixer: AudioMixerController

    private var clipboardCancellable: AnyCancellable?

    init(
        clipboard: ClipboardHistoryViewModel,
        controlCenter: ControlCenterModel,
        notes: NoteController,
        inputTools: InputToolsController,
        systemMetrics: SystemMetricsController,
        audioMixer: AudioMixerController
    ) {
        self.clipboard = clipboard
        settings = clipboard.settings
        launchAtLoginService = clipboard.launchAtLoginService
        self.controlCenter = controlCenter
        self.notes = notes
        self.inputTools = inputTools
        self.systemMetrics = systemMetrics
        self.audioMixer = audioMixer
        clipboardCancellable = clipboard.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var collections: [ClipboardCollection] { clipboard.collections }
    var pasteStackItems: [ClipboardItem] { clipboard.pasteStackItems }
    var storageMetrics: StorageMetrics { clipboard.storageMetrics }
    var migrationStatus: String { clipboard.migrationStatus }
    var cleanupMessage: String? { clipboard.cleanupMessage }
    var globalShortcutError: String? { clipboard.globalShortcutError }
    var archiveStatusMessage: String? { clipboard.archiveStatusMessage }
    var errorMessage: String? { clipboard.errorMessage }
    var isPrivateMode: Bool { clipboard.isPrivateMode }
    var isPaused: Bool { clipboard.isPaused }
    var pauseUntil: Date? { clipboard.pauseUntil }

    func setLaunchAtLogin(_ enabled: Bool) { clipboard.setLaunchAtLogin(enabled) }
    func setPrivateModeEnabled(_ enabled: Bool) { clipboard.setPrivateModeEnabled(enabled) }
    func enablePrivateMode(minutes: Int) { clipboard.enablePrivateMode(minutes: minutes) }
    func pauseRecording(minutes: Int) { clipboard.pauseRecording(minutes: minutes) }
    func resumeRecording() { clipboard.resumeRecording() }
    func resetPasteStack() { clipboard.resetPasteStack() }
    func createCollection(named name: String) { clipboard.createCollection(named: name) }
    func deleteCollection(_ collection: ClipboardCollection) { clipboard.deleteCollection(collection) }
    func confirmClearHistory() { clipboard.confirmClearHistory() }
    func runRetentionCleanup() async { await clipboard.runRetentionCleanup() }
    func refreshStorageInformation() async { await clipboard.refreshStorageInformation() }

    func exportArchive(
        mode: ClipboardExportMode,
        includeImagesAndDocuments: Bool,
        includeFileReferences: Bool = true,
        password: String? = nil
    ) {
        clipboard.exportArchive(
            mode: mode,
            includeImagesAndDocuments: includeImagesAndDocuments,
            includeFileReferences: includeFileReferences,
            password: password
        )
    }

    func importArchive(password: String?) {
        clipboard.importArchive(password: password)
    }

    func importStorageRecoveryArchive(password: String) {
        clipboard.importStorageRecoveryArchive(password: password)
    }

    func beginPanelModalInteraction() {
        clipboard.beginPanelModalInteraction?()
    }

    func endPanelModalInteraction() {
        clipboard.endPanelModalInteraction?()
    }

    func notifyMenuCommandDidRun() {
        clipboard.menuCommandDidRun?()
    }
}
