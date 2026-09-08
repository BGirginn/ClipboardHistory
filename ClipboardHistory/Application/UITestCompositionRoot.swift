#if CLIPBOARD_HISTORY_TEST_HOST
import AppKit
import Foundation

@MainActor
enum UITestCompositionRoot {
    static func makeModel(environment: [String: String]) -> AppModel? {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let requested = environment["CLIPBOARD_HISTORY_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
        let allowedRoots = [temporary, URL(fileURLWithPath: "/private/tmp")]
        let root = requested.flatMap { candidate in
            allowedRoots.contains { candidate.path.hasPrefix($0.path + "/") }
                && candidate.lastPathComponent.hasPrefix("ClipboardHistory-") ? candidate : nil
        } ?? temporary.appending(path: "ClipboardHistory-UITesting-\(UUID().uuidString)")
        let suite = environment["CLIPBOARD_HISTORY_TEST_DEFAULTS"]
            ?? "ClipboardHistory.UITesting.\(UUID().uuidString)"
        guard suite.hasPrefix("ClipboardHistory."), let defaults = UserDefaults(suiteName: suite) else {
            AppLog.lifecycle.error("UI test defaults must use an isolated suite")
            return nil
        }
        defaults.set(false, forKey: "closePanelAfterCopying")
        defaults.set(1, forKey: "closePanelAfterCopyingMigrationVersion")
        let pasteboard = NSPasteboard(name: .init("ClipboardHistory.UITesting.\(UUID().uuidString)"))
        let services = UITestSystemServices()
        let model = AppModel(
            storage: StorageService(baseDirectory: root, fileManager: UITestFileManager(root: root), encryptionService: .ephemeral()),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: services,
            settings: AppSettings(defaults: defaults),
            launchAtLoginService: LaunchAtLoginService(backend: services),
            sensitiveContentAuthenticator: services,
            workspaceRevealer: services,
            inputEventTapCoordinator: services,
            systemMetricsController: SystemMetricsController(provider: services, defaults: defaults),
            audioMixerController: AudioMixerController(
                discovery: services, engine: services, browserBridge: services,
                extensionInstaller: BrowserExtensionInstaller(supportRoot: root, workspace: services),
                safariPreferencesOpener: { _, completion in completion(nil) }, defaults: defaults
            ),
            controlCenter: ControlCenterModel(store: MenuBarConfigurationStore(defaults: defaults)),
            startsAutomatically: false
        )
        model.uiTestRoot = root
        return model
    }
}
#endif
