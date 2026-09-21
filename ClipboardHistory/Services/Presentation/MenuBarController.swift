import AppKit
import Combine
import Foundation
import os.signpost
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    var statusItems: [MenuBarItemID: NSStatusItem] = [:]
    var renderedStatusStates: [MenuBarItemID: MenuBarRenderedState] = [:]
    var metricStripViews: [MenuBarItemID: MenuBarMetricStripView] = [:]
    var activeAnchorID: MenuBarItemID = .controlCenter
    private let popover: NSPopover
    let drawerPopover: NSPopover
    let dependencies: MenuBarControllerDependencies
    private let popoverAnchor: (() -> NSView?)?
    private let applicationWindowPresenter: (any ApplicationWindowPresenting)?
    var detachablePanel: NSPanel?
    let appModel: AppModel
    private let quickLookService: any QuickLookPresenting
    private let shortcutBackend: any GlobalShortcutBackend
    private var shortcutCancellable: AnyCancellable?
    private var shortcutPresetCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var panelEdgeCancellable: AnyCancellable?
    private var shortcutErrorCancellable: AnyCancellable?
    var keyboardCleaningCancellable: AnyCancellable?
    var scrollReversalCancellable: AnyCancellable?
    var audioMixerCancellable: AnyCancellable?
    private var menuBarConfigurationCancellable: AnyCancellable?
    private var systemMetricsCancellable: AnyCancellable?
    private var routeCancellable: AnyCancellable?
    private var settingsSubsectionCancellable: AnyCancellable?
    private var panelClosingTask: Task<Void, Never>?
    private var popoverReanchorTask: Task<Void, Never>?
    private var panelCloseCoordinator: PanelCloseCoordinator?
    var isStopped = false
    private let popoverDemandSource = SamplingDemandSource()
    private let detachablePanelDemandSource = SamplingDemandSource()
    let presentationLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "ClipboardHistory",
        category: "PopoverPresentation"
    )
    var presentationSignpostID: OSSignpostID?
    private lazy var shortcutMonitor = GlobalShortcutMonitor(
        action: { [weak self] in self?.shortcutPressed() },
        releaseAction: { [weak self] in self?.shortcutReleased() },
        backend: shortcutBackend
    )

    var navigationGeneration: UInt = 0

    private var viewModel: ClipboardHistoryViewModel { appModel.clipboard }

    init(
        appModel: AppModel,
        dependencies: MenuBarControllerDependencies? = nil,
        panelEventMonitor: any PanelEventMonitoring = SystemPanelEventMonitor(),
        shortcutBackend: (any GlobalShortcutBackend)? = nil,
        applicationWindowPresenter: (any ApplicationWindowPresenting)? = nil,
        popoverAnchor: (() -> NSView?)? = nil
    ) {
        self.appModel = appModel
        let dependencies = MenuBarControllerDependencies.resolve(for: appModel, provided: dependencies)
        let shortcutBackend = MenuBarControllerDependencies.resolveShortcut(for: appModel, provided: shortcutBackend)
        self.dependencies = dependencies
        self.shortcutBackend = shortcutBackend
        self.applicationWindowPresenter = applicationWindowPresenter
        self.popoverAnchor = popoverAnchor
        popover = dependencies.makePopover()
        drawerPopover = dependencies.makeDrawerPopover()
        quickLookService = dependencies.quickLookPresenter
        super.init()
        appModel.requestOpenWindow = { [weak self] in
            guard let self else { return }
            self.closePopoverNow()
            self.applicationWindowPresenter?.showActiveFeature()
        }

        rebuildStatusItems()

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 500)
        ensurePopoverContent()
        drawerPopover.behavior = .transient
        drawerPopover.animates = true
        drawerPopover.contentSize = NSSize(width: 380, height: 132)
        ensureDrawerContent()
        panelCloseCoordinator = PanelCloseCoordinator(
            eventMonitor: panelEventMonitor,
            isPanelShown: { [weak self] in self?.popover.isShown == true },
            isPanelEvent: { [weak self] event in
                event.window === self?.popover.contentViewController?.view.window
            },
            isStatusItemEvent: { [weak self] event in self?.isStatusItemEvent(event) == true },
            closePanel: { [weak self] in self?.closePopover() }
        )
        appModel.clipboard.requestClosePanel = { [weak self] in self?.closePopover() }
        appModel.clipboard.menuCommandDidRun = { [weak self] in
            self?.panelCloseCoordinator?.menuCommandDidRun()
        }
        appModel.clipboard.beginPanelModalInteraction = { [weak self] in
            self?.panelCloseCoordinator?.beginModalInteraction()
        }
        appModel.clipboard.endPanelModalInteraction = { [weak self] in
            self?.panelCloseCoordinator?.endModalInteraction()
        }
        appModel.clipboard.requestPreview = { [weak self] item in
            guard let self else { return }
            self.quickLookService.show(item: item, storage: self.appModel.clipboard.storage)
        }
        appModel.clipboard.privateModeDidChange = { [weak self] _ in
            self?.refreshConditionalStatusItems()
        }

        shortcutCancellable = appModel.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.shortcutMonitor.setEnabled(
                    enabled,
                    shortcut: self.appModel.settings.globalShortcut
                )
            }
        shortcutPresetCancellable = appModel.settings.$globalShortcutPresetID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] presetID in
                guard let self else { return }
                let shortcut = GlobalShortcut.presets.first { $0.id == presetID }
                    ?? GlobalShortcut.defaultShortcut
                self.shortcutMonitor.setEnabled(
                    self.appModel.settings.globalShortcutEnabled,
                    shortcut: shortcut
                )
            }
        shortcutMonitor.setEnabled(
            appModel.settings.globalShortcutEnabled,
            shortcut: appModel.settings.globalShortcut
        )
        shortcutErrorCancellable = shortcutMonitor.$registrationError
            .removeDuplicates()
            .sink { [weak appModel] message in
                appModel?.clipboard.setGlobalShortcutError(message)
            }
        observeConditionalMenuBarStates()
        appearanceCancellable = appModel.settings.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
        panelEdgeCancellable = appModel.settings.$panelScreenEdge
            .removeDuplicates()
            .sink { [weak self] edge in self?.positionDetachablePanel(screenEdge: edge) }
        menuBarConfigurationCancellable = appModel.controlCenter.$configuration
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.rebuildStatusItems(configuration: configuration)
                self?.updateVisiblePresentationDemands(configuration: configuration)
            }
        routeCancellable = appModel.router.$activeFeature
            .removeDuplicates()
            .sink { [weak self] feature in
                self?.updateVisiblePresentationDemands(presentedFeature: feature)
            }
        settingsSubsectionCancellable = appModel.router.$settingsSubsection
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self,
                          self.appModel.router.activeFeature == .settings else { return }
                    self.updateVisiblePresentationDemands()
                }
            }
        systemMetricsCancellable = appModel.systemMetrics.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.updateMetricStatusItems(snapshot: snapshot)
            }
        updateStatusIcon()
    }

    var isPopoverShown: Bool {
        popover.isShown || detachablePanel?.isVisible == true
    }

    var isDrawerShown: Bool {
        drawerPopover.isShown
    }

    var shortcutRegistrationError: String? {
        shortcutMonitor.registrationError
    }

    func openFeature(
        _ feature: AppFeature,
        anchorID: MenuBarItemID? = nil,
        preparesDestination: Bool = true,
        settingsSection: AppSettingsSection? = nil
    ) {
        navigationGeneration &+= 1
        let generation = navigationGeneration
        let routeGeneration = appModel.router.navigationGeneration
        Task { [weak self] in
            guard let self else { return }
            if self.appModel.router.activeFeature == .notes, feature != .notes {
                let outcome = await self.appModel.notes.flushPendingSave()
                guard outcome.allowsTransition else { return }
            }
            guard generation == self.navigationGeneration, !self.isStopped,
                  routeGeneration == self.appModel.router.navigationGeneration else { return }
            if self.isPopoverShown {
                if let anchorID,
                   self.activeAnchorID != anchorID,
                   self.appModel.settings.panelPresentationMode == .popover {
                    self.popover.performClose(nil)
                    self.activeAnchorID = anchorID
                    self.showPopover(
                        destination: feature,
                        anchorID: anchorID,
                        preparesDestination: preparesDestination,
                        settingsSection: settingsSection
                    )
                } else if preparesDestination {
                    self.prepare(destination: feature, settingsSection: settingsSection)
                }
            } else {
                self.showPopover(
                    destination: feature,
                    anchorID: anchorID,
                    preparesDestination: preparesDestination,
                    settingsSection: settingsSection
                )
            }
        }
    }

    private func prepare(
        destination: AppFeature,
        settingsSection: AppSettingsSection? = nil
    ) {
        switch destination {
        case .controlCenter:
            appModel.prepareForNormalPresentation()
        case .clipboard:
            appModel.prepareForClipboardShortcut()
        case .notes:
            appModel.showNoteList()
        case .keyboardCleaning:
            appModel.showKeyboardCleaning()
        case .scrollReverse:
            appModel.showScrollReverse()
        case .systemMonitor:
            appModel.showSystemMonitor()
        case .audioMixer:
            appModel.showAudioMixer()
        case .menuBarCustomization:
            appModel.showMenuBarCustomization()
        case .settings:
            appModel.openSettings(section: settingsSection)
        }
    }

    @discardableResult
    func showPopover(
        destination: AppFeature,
        anchorID: MenuBarItemID? = nil,
        preparesDestination: Bool = true,
        capturesPasteTargetApplication: Bool = true,
        settingsSection: AppSettingsSection? = nil
    ) -> Bool {
        drawerPopover.performClose(nil)
        beginPresentationSignpost()
        if preparesDestination {
            prepare(destination: destination, settingsSection: settingsSection)
        }
        if let anchorID { activeAnchorID = anchorID }
        if appModel.settings.panelPresentationMode == .detachable {
            markPresentationPrepared()
            showDetachablePanel()
            endPresentationSignpost()
            return true
        }
        guard let anchor = popoverAnchor?()
            ?? statusItems[activeAnchorID]?.button
            ?? statusItems.values.first?.button else {
            applicationWindowPresenter?.showActiveFeature()
            endPresentationSignpost()
            return applicationWindowPresenter?.isWindowVisible == true
        }
        preparePopoverContent()
        markPresentationPrepared()
        if capturesPasteTargetApplication {
            appModel.clipboard.capturePasteTargetApplication()
        }
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        return popover.isShown
    }

    func closePopover() {
        guard panelClosingTask == nil else { return }
        guard appModel.router.activeFeature == .notes,
              appModel.notes.hasPendingChanges else {
            closePopoverNow()
            return
        }
        panelClosingTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.appModel.notes.flushPendingSave()
            if outcome.allowsTransition {
                self.closePopoverNow()
            }
            self.panelClosingTask = nil
        }
    }

    func closePopoverNow() {
        popoverReanchorTask?.cancel()
        popoverReanchorTask = nil
        shortcutMonitor.cancelHeldShortcut()
        quickLookService.close()
        popover.performClose(nil)
        drawerPopover.performClose(nil)
        detachablePanel?.orderOut(nil)
        appModel.updatePresentationDemand(for: detachablePanelDemandSource, isVisible: false)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        panelClosingTask?.cancel()
        panelClosingTask = nil
        popoverReanchorTask?.cancel()
        popoverReanchorTask = nil
        panelCloseCoordinator?.stop()
        shortcutMonitor.cancelHeldShortcut()
        shortcutMonitor.unregister()
        shortcutCancellable = nil
        shortcutPresetCancellable = nil
        appearanceCancellable = nil
        panelEdgeCancellable = nil
        shortcutErrorCancellable = nil
        stopConditionalMenuBarObservation()
        menuBarConfigurationCancellable = nil
        systemMetricsCancellable = nil
        routeCancellable = nil
        settingsSubsectionCancellable = nil
        appModel.inputTools.prepareForShutdown()
        quickLookService.close()
        popover.close()
        drawerPopover.close()
        detachablePanel?.close()
        appModel.updatePresentationDemand(for: popoverDemandSource, isVisible: false)
        appModel.updatePresentationDemand(for: detachablePanelDemandSource, isVisible: false)
        appModel.systemMetrics.setDemand(nil, for: .menuBar)
        statusItems.values.forEach(dependencies.removeStatusItem)
        statusItems.removeAll()
        renderedStatusStates.removeAll()
        metricStripViews.removeAll()
    }

    func popoverWillShow(_ notification: Notification) {
        panelCloseCoordinator?.start()
    }

    func popoverDidShow(_ notification: Notification) {
        appModel.updatePresentationDemand(for: popoverDemandSource, isVisible: true)
        endPresentationSignpost()
    }

    func popoverDidClose(_ notification: Notification) {
        appModel.updatePresentationDemand(for: popoverDemandSource, isVisible: false)
        presentationSignpostID = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSPanel === detachablePanel else { return }
        appModel.updatePresentationDemand(for: detachablePanelDemandSource, isVisible: false)
    }

    private func shortcutPressed() {
        switch appModel.settings.shortcutActivationMode {
        case .toggle:
            if isPopoverShown {
                closePopover()
            } else {
                showPopover(destination: .clipboard)
            }
        case .hold:
            if !popover.isShown { showPopover(destination: .clipboard) }
        }
    }

    private func shortcutReleased() {
        guard appModel.settings.shortcutActivationMode == .hold,
              popover.isShown else { return }
        appModel.clipboard.pasteSelectedToActiveApp()
    }

    private func showDetachablePanel() {
        let panel = ensureDetachablePanel()
        appModel.clipboard.capturePasteTargetApplication()
        NSApp.activate()
        positionDetachablePanel()
        panel.makeKeyAndOrderFront(nil)
        appModel.updatePresentationDemand(for: detachablePanelDemandSource, isVisible: true)
    }

    private func ensurePopoverContent() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(
            rootView: AppShellView(model: appModel)
        )
    }

    private func preparePopoverContent() {
        ensurePopoverContent()
        guard let contentView = popover.contentViewController?.view else { return }
        if contentView.frame.size != popover.contentSize {
            contentView.setFrameSize(popover.contentSize)
        }
        contentView.layoutSubtreeIfNeeded()
    }

    private func updateVisiblePresentationDemands(
        configuration: MenuBarConfiguration? = nil,
        presentedFeature: AppFeature? = nil
    ) {
        appModel.updatePresentationDemand(
            for: popoverDemandSource,
            isVisible: popover.isShown,
            configuration: configuration,
            presentedFeature: presentedFeature
        )
        appModel.updatePresentationDemand(
            for: detachablePanelDemandSource,
            isVisible: detachablePanel?.isVisible == true,
            configuration: configuration,
            presentedFeature: presentedFeature
        )
    }

    private func ensureDetachablePanel() -> NSPanel {
        if let detachablePanel { return detachablePanel }
        let panel = dependencies.makePanel(appModel)
        panel.delegate = self
        detachablePanel = panel
        applyAppearance(viewModel.settings.appearance)
        return panel
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        let resolvedAppearance = appearance.nativeAppearance
        popover.appearance = resolvedAppearance
        drawerPopover.appearance = resolvedAppearance
        detachablePanel?.appearance = resolvedAppearance
    }

    func reanchorPopoverIfNeeded(removesActiveAnchor: Bool) {
        guard removesActiveAnchor,
              popover.isShown,
              popoverAnchor == nil,
              appModel.settings.panelPresentationMode == .popover else { return }
        let destination = appModel.router.activeFeature
        popover.performClose(nil)
        popoverReanchorTask?.cancel()
        popoverReanchorTask = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            for attempt in 0..<10 {
                guard !Task.isCancelled,
                      self.appModel.settings.panelPresentationMode == .popover else { return }
                if !self.popover.isShown && self.showPopover(
                    destination: destination,
                    anchorID: self.activeAnchorID,
                    preparesDestination: false,
                    capturesPasteTargetApplication: false
                ) {
                    self.popoverReanchorTask = nil
                    return
                }
                guard attempt < 9 else { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            AppLog.lifecycle.error(
                "Menu bar popover could not re-anchor after status-item replacement"
            )
            self.popoverReanchorTask = nil
        }
    }

}
