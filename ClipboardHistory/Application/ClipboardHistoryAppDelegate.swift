import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardHistoryAppDelegate: NSObject, NSApplicationDelegate {
    typealias AppModelFactory = @MainActor () -> AppModel
    typealias ApplicationWindowPresenterFactory = @MainActor (AppModel) -> any ApplicationWindowPresenting
    typealias MenuBarControllerFactory = @MainActor (
        AppModel,
        any ApplicationWindowPresenting
    ) -> MenuBarController
    typealias ActivationPolicySetter = @MainActor (NSApplication.ActivationPolicy) -> Bool
    typealias TerminationReply = @MainActor (NSApplication, Bool) -> Void

    private let environment: [String: String]
    private let arguments: [String]
    private let appModelFactory: AppModelFactory
    private let applicationWindowPresenterFactory: ApplicationWindowPresenterFactory
    private let menuBarControllerFactory: MenuBarControllerFactory
    private let activationPolicySetter: ActivationPolicySetter
    private let terminationReply: TerminationReply
    private var appModel: AppModel?
    private var applicationWindowPresenter: (any ApplicationWindowPresenting)?
    private var settingsWindowPresenter: (any SettingsWindowPresenting)?
    private var menuBarController: MenuBarController?
    private var menuBarConfigurationCancellable: AnyCancellable?
    private var terminationTask: Task<Void, Never>?
    override convenience init() {
        #if CLIPBOARD_HISTORY_TEST_HOST
        var environment = ProcessInfo.processInfo.environment
        environment["CLIPBOARD_HISTORY_TEST_HOST_ENTRY"] = "1"
        #else
        let environment = ProcessInfo.processInfo.environment
        #endif
        self.init(
            environment: environment,
            arguments: ProcessInfo.processInfo.arguments,
            appModelFactory: { AppModel() },
            applicationWindowPresenterFactory: { ApplicationWindowController(appModel: $0) },
            menuBarControllerFactory: {
                MenuBarController(appModel: $0, applicationWindowPresenter: $1)
            },
            activationPolicySetter: { NSApplication.shared.setActivationPolicy($0) },
            terminationReply: { $0.reply(toApplicationShouldTerminate: $1) }
        )
    }

    init(
        environment: [String: String],
        arguments: [String] = [],
        appModelFactory: @escaping AppModelFactory,
        applicationWindowPresenterFactory: @escaping ApplicationWindowPresenterFactory = {
            ApplicationWindowController(appModel: $0)
        },
        menuBarControllerFactory: @escaping MenuBarControllerFactory,
        activationPolicySetter: @escaping ActivationPolicySetter = {
            NSApplication.shared.setActivationPolicy($0)
        },
        terminationReply: @escaping TerminationReply = {
            $0.reply(toApplicationShouldTerminate: $1)
        }
    ) {
        self.environment = environment
        self.arguments = arguments
        self.appModelFactory = appModelFactory
        self.applicationWindowPresenterFactory = applicationWindowPresenterFactory
        self.menuBarControllerFactory = menuBarControllerFactory
        self.activationPolicySetter = activationPolicySetter
        self.terminationReply = terminationReply
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if CLIPBOARD_HISTORY_TEST_HOST
        if environment["CLIPBOARD_HISTORY_UI_TESTING"] == "1" {
            launchForUITesting()
            return
        }
        if environment["CLIPBOARD_HISTORY_TEST_HOST_ENTRY"] == "1" {
            AppLog.lifecycle.debug("Application services disabled for hosted tests")
            return
        }
        #endif
        let appModel = appModelFactory()
        let usesApplicationWindow = configurePresentation(for: appModel)
        if !arguments.contains("--background-launch") {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.showControlCenterInterface()
            }
        }
        let interface = usesApplicationWindow ? "application-window" : "menu-bar"
        AppLog.lifecycle.notice("Application launched; interface=\(interface, privacy: .public)")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showControlCenterInterface(preservingActiveFeature: true)
        return false
    }

    #if CLIPBOARD_HISTORY_TEST_HOST
    private func launchForUITesting() {
        guard let appModel = UITestCompositionRoot.makeModel(environment: environment) else { return }
        appModel.controlCenter.setShownInControlCenter(true, for: .audioMixer)
        let seedItems = [
            ClipboardItem(type: .text, text: "Alpha clipboard item", hash: "ui-alpha"),
            ClipboardItem(type: .text, text: "Beta clipboard item", hash: "ui-beta"),
            ClipboardItem(type: .text, text: "Gamma clipboard item", hash: "ui-gamma")
        ]
        let seedCollection = ClipboardCollection(name: "Coverage Collection")
        Task { [weak self] in
            do {
                for item in seedItems {
                    try await appModel.clipboard.storage.upsertThrowing(item)
                }
                try await appModel.clipboard.storage.upsertCollection(seedCollection)
                appModel.clipboard.items = seedItems
                appModel.clipboard.collections = [seedCollection]
                appModel.clipboard.refreshDisplayedItems()
                _ = self?.configurePresentation(for: appModel)
                self?.showControlCenterInterface()
                AppLog.lifecycle.notice("Application launched; interface=isolated-ui-test")
            } catch {
                AppLog.lifecycle.error("Isolated UI test data could not be initialized")
            }
        }
    }

    #endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }
        let terminationReply = terminationReply
        terminationTask = Task { [weak self, weak sender] in
            let outcome = await appModel.shutdown()
            let canTerminate = outcome.allowsTermination
            guard let self else {
                if let sender {
                    terminationReply(sender, canTerminate)
                }
                return
            }
            if canTerminate {
                self.menuBarController?.stop()
                self.applicationWindowPresenter?.stop()
                if let sender { terminationReply(sender, true) }
            } else {
                self.terminationTask = nil
                self.showActiveInterface()
                if let sender { terminationReply(sender, false) }
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if terminationTask == nil {
            appModel?.prepareForShutdown()
        }
        terminationTask?.cancel()
        terminationTask = nil
        menuBarConfigurationCancellable?.cancel()
        menuBarConfigurationCancellable = nil
        menuBarController?.stop()
        settingsWindowPresenter?.stop()
        applicationWindowPresenter?.stop()
        menuBarController = nil
        settingsWindowPresenter = nil
        applicationWindowPresenter = nil
        appModel = nil
    }

    private func configurePresentation(
        for appModel: AppModel
    ) -> Bool {
        self.appModel = appModel
        let windowPresenter = applicationWindowPresenterFactory(appModel)
        applicationWindowPresenter = windowPresenter
        let menuBarController = menuBarControllerFactory(appModel, windowPresenter)
        self.menuBarController = menuBarController
        let settingsWindowPresenter = SettingsWindowController(appModel: appModel)
        self.settingsWindowPresenter = settingsWindowPresenter
        appModel.requestOpenSettings = { [weak self] section in
            self?.settingsWindowPresenter?.show(section: section)
        }
        appModel.requestCloseSettings = { [weak self] in
            self?.settingsWindowPresenter?.close()
        }
        menuBarConfigurationCancellable = appModel.controlCenter.$configuration
            .map(\.showsControlCenterItem)
            .removeDuplicates()
            .sink { [weak self] showsControlCenterItem in
                self?.applyActivationPolicy(showsControlCenterItem: showsControlCenterItem)
            }
        return !appModel.controlCenter.configuration.showsControlCenterItem
    }

    private func applyActivationPolicy(showsControlCenterItem: Bool) {
        let policy: NSApplication.ActivationPolicy = showsControlCenterItem ? .accessory : .regular
        if activationPolicySetter(policy) { return }
        AppLog.lifecycle.error(
            "Application activation policy could not change to \(String(describing: policy), privacy: .public)"
        )
        if !showsControlCenterItem {
            appModel?.controlCenter.setControlCenterItemVisible(true)
        }
    }

    private func showControlCenterInterface(preservingActiveFeature: Bool = false) {
        guard let appModel else { return }
        if appModel.controlCenter.configuration.showsControlCenterItem {
            menuBarController?.showControlCenter()
        } else {
            menuBarController?.closePopover()
            if preservingActiveFeature {
                applicationWindowPresenter?.showActiveFeature()
            } else {
                applicationWindowPresenter?.showControlCenter()
            }
        }
    }

    private func showActiveInterface() {
        guard let appModel else { return }
        if appModel.controlCenter.configuration.showsControlCenterItem {
            menuBarController?.showActiveFeature()
        } else {
            applicationWindowPresenter?.showActiveFeature()
        }
    }
}
