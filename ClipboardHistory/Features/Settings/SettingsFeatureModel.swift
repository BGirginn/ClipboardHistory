import Combine
import Foundation

@MainActor
final class SettingsFeatureModel: ObservableObject {
    let clipboard: ClipboardHistoryViewModel
    var settings: AppSettings
    let lockService: AppLockService
    let launchAtLoginService: LaunchAtLoginService
    let controlCenter: ControlCenterModel
    let systemMetrics: SystemMetricsController
    let audioMixer: AudioMixerController

    private var clipboardCancellable: AnyCancellable?

    init(
        clipboard: ClipboardHistoryViewModel,
        controlCenter: ControlCenterModel,
        systemMetrics: SystemMetricsController,
        audioMixer: AudioMixerController
    ) {
        self.clipboard = clipboard
        settings = clipboard.settings
        lockService = clipboard.lockService
        launchAtLoginService = clipboard.launchAtLoginService
        self.controlCenter = controlCenter
        self.systemMetrics = systemMetrics
        self.audioMixer = audioMixer
        clipboardCancellable = clipboard.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    convenience init(clipboard: ClipboardHistoryViewModel) {
        self.init(
            clipboard: clipboard,
            controlCenter: ControlCenterModel(),
            systemMetrics: SystemMetricsController(),
            audioMixer: AudioMixerController()
        )
    }

    var collections: [ClipboardCollection] { clipboard.collections }
    var pasteStackItems: [ClipboardItem] { clipboard.pasteStackItems }
    var storageMetrics: StorageMetrics { clipboard.storageMetrics }
    var migrationStatus: String { clipboard.migrationStatus }
    var globalShortcutError: String? { clipboard.globalShortcutError }
    var archiveStatusMessage: String? { clipboard.archiveStatusMessage }
    var errorMessage: String? { clipboard.errorMessage }
    var isApplicationLockEnabled: Bool { clipboard.isApplicationLockEnabled }
    var isLocked: Bool { clipboard.isLocked }
    var isPrivateMode: Bool { clipboard.isPrivateMode }
    var isPaused: Bool { clipboard.isPaused }
    var pauseUntil: Date? { clipboard.pauseUntil }

    func setLaunchAtLogin(_ enabled: Bool) { clipboard.setLaunchAtLogin(enabled) }
    func setApplicationLockEnabled(_ enabled: Bool) { clipboard.setApplicationLockEnabled(enabled) }
    func lock() { clipboard.lock() }
    func unlock() { clipboard.unlock() }
    func setPrivateModeEnabled(_ enabled: Bool) { clipboard.setPrivateModeEnabled(enabled) }
    func enablePrivateMode(minutes: Int) { clipboard.enablePrivateMode(minutes: minutes) }
    func pauseRecording(minutes: Int) { clipboard.pauseRecording(minutes: minutes) }
    func resumeRecording() { clipboard.resumeRecording() }
    func resetPasteStack() { clipboard.resetPasteStack() }
    func createCollection(named name: String) { clipboard.createCollection(named: name) }
    func deleteCollection(_ collection: ClipboardCollection) { clipboard.deleteCollection(collection) }
    func clearHistory() { clipboard.clearHistory() }
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
}
