import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    var statusItems: [MenuBarItemID: NSStatusItem] = [:]
    var renderedStatusStates: [MenuBarItemID: MenuBarRenderedState] = [:]
    var activeAnchorID: MenuBarItemID = .controlCenter
    private let popover: NSPopover
    let dependencies: MenuBarControllerDependencies
    private let popoverAnchor: (() -> NSView?)?
    private var detachablePanel: NSPanel?
    let appModel: AppModel
    private let quickLookService: any QuickLookPresenting
    private let shortcutBackend: any GlobalShortcutBackend
    private var shortcutCancellable: AnyCancellable?
    private var shortcutPresetCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var panelEdgeCancellable: AnyCancellable?
    private var shortcutErrorCancellable: AnyCancellable?
    private var keyboardCleaningCancellable: AnyCancellable?
    private var scrollReversalCancellable: AnyCancellable?
    private var menuBarConfigurationCancellable: AnyCancellable?
    private var systemMetricsCancellable: AnyCancellable?
    private var audioMixerCancellable: AnyCancellable?
    private var panelClosingTask: Task<Void, Never>?
    private var activityMonitor: Any?
    private var panelCloseCoordinator: PanelCloseCoordinator?
    private lazy var shortcutMonitor = GlobalShortcutMonitor(
        action: { [weak self] in self?.shortcutPressed() },
        releaseAction: { [weak self] in self?.shortcutReleased() },
        backend: shortcutBackend
    )

    private var viewModel: ClipboardHistoryViewModel { appModel.clipboard }

    init(
        appModel: AppModel,
        dependencies: MenuBarControllerDependencies = .live,
        panelEventMonitor: any PanelEventMonitoring = SystemPanelEventMonitor(),
        shortcutBackend: any GlobalShortcutBackend = SystemGlobalShortcutBackend(),
        popoverAnchor: (() -> NSView?)? = nil
    ) {
        self.appModel = appModel
        self.dependencies = dependencies
        self.shortcutBackend = shortcutBackend
        self.popoverAnchor = popoverAnchor
        popover = dependencies.makePopover()
        quickLookService = dependencies.quickLookPresenter
        super.init()

        rebuildStatusItems()

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 500)
        preparePopoverContent()
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
            quickLookService.show(item: item, storage: appModel.clipboard.storage)
        }
        appModel.clipboard.privateModeDidChange = { [weak self] _ in self?.updateStatusIcon() }

        shortcutCancellable = appModel.settings.$globalShortcutEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                shortcutMonitor.setEnabled(
                    enabled,
                    shortcut: appModel.settings.globalShortcut
                )
            }
        shortcutPresetCancellable = appModel.settings.$globalShortcutPresetID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                shortcutMonitor.setEnabled(
                    appModel.settings.globalShortcutEnabled,
                    shortcut: appModel.settings.globalShortcut
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
        keyboardCleaningCancellable = appModel.inputTools.keyboardCleaning.$isActive
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateStatusIcon() }
        scrollReversalCancellable = appModel.inputTools.scrollReversal.$isActive
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateStatusIcon() }
        appearanceCancellable = appModel.settings.$appearance
            .removeDuplicates()
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
        panelEdgeCancellable = appModel.settings.$panelScreenEdge
            .removeDuplicates()
            .sink { [weak self] _ in self?.positionDetachablePanel() }
        menuBarConfigurationCancellable = appModel.controlCenter.$configuration
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.rebuildStatusItems(configuration: configuration)
            }
        systemMetricsCancellable = appModel.systemMetrics.$snapshot
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateStatusIcon() }
        audioMixerCancellable = appModel.audioMixer.$applications
            .sink { [weak self] _ in self?.updateStatusIcon() }
        updateStatusIcon()
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .keyDown, .keyUp, .flagsChanged,
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .scrollWheel
            ]
        ) { [weak self] event in
            if self?.isPopoverShown == true {
                self?.appModel.lockService.recordActivity()
            }
            return event
        }
    }

    var isPopoverShown: Bool {
        popover.isShown || detachablePanel?.isVisible == true
    }

    var shortcutRegistrationError: String? {
        shortcutMonitor.registrationError
    }

    func togglePopover() {
        isPopoverShown ? closePopover() : showPopover()
    }

    func showPopover() {
        showPopover(destination: .controlCenter, anchorID: .controlCenter)
    }

    func showControlCenter() {
        showPopover(destination: .controlCenter, anchorID: .controlCenter)
    }

    func showActiveFeature() {
        showPopover(
            destination: appModel.router.activeFeature,
            anchorID: activeAnchorID,
            preparesDestination: false
        )
    }

    func openFeature(
        _ feature: AppFeature,
        anchorID: MenuBarItemID? = nil,
        preparesDestination: Bool = true
    ) {
        Task { [weak self] in
            guard let self else { return }
            if appModel.router.activeFeature == .notes, feature != .notes {
                let outcome = await appModel.notes.flushPendingSave()
                guard outcome.allowsTransition else { return }
            }
            if isPopoverShown {
                if let anchorID,
                   activeAnchorID != anchorID,
                   appModel.settings.panelPresentationMode == .popover {
                    popover.performClose(nil)
                    activeAnchorID = anchorID
                    showPopover(
                        destination: feature,
                        anchorID: anchorID,
                        preparesDestination: preparesDestination
                    )
                } else if preparesDestination {
                    prepare(destination: feature)
                }
            } else {
                showPopover(
                    destination: feature,
                    anchorID: anchorID,
                    preparesDestination: preparesDestination
                )
            }
        }
    }

    private func prepare(destination: AppFeature) {
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
            appModel.openSettings()
        }
    }

    private func showPopover(
        destination: AppFeature,
        anchorID: MenuBarItemID? = nil,
        preparesDestination: Bool = true
    ) {
        if preparesDestination { prepare(destination: destination) }
        if let anchorID { activeAnchorID = anchorID }
        if appModel.settings.panelPresentationMode == .detachable {
            showDetachablePanel()
            return
        }
        guard let anchor = popoverAnchor?()
            ?? statusItems[activeAnchorID]?.button
            ?? statusItems.values.first?.button else { return }
        preparePopoverContent()
        appModel.clipboard.capturePasteTargetApplication()
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        appModel.lockService.recordActivity()
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
            let outcome = await appModel.notes.flushPendingSave()
            if outcome.allowsTransition {
                closePopoverNow()
            }
            panelClosingTask = nil
        }
    }

    private func closePopoverNow() {
        shortcutMonitor.cancelHeldShortcut()
        quickLookService.close()
        popover.performClose(nil)
        detachablePanel?.orderOut(nil)
    }

    func stop() {
        panelClosingTask?.cancel()
        panelClosingTask = nil
        if let activityMonitor {
            NSEvent.removeMonitor(activityMonitor)
            self.activityMonitor = nil
        }
        appModel.inputTools.prepareForShutdown()
        panelCloseCoordinator?.stop()
        shortcutMonitor.cancelHeldShortcut()
        shortcutMonitor.unregister()
        quickLookService.close()
        popover.close()
        detachablePanel?.close()
        statusItems.values.forEach(dependencies.removeStatusItem)
        statusItems.removeAll()
        renderedStatusStates.removeAll()
    }

    func popoverWillShow(_ notification: Notification) {
        panelCloseCoordinator?.start()
        appModel.lockService.recordActivity()
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
        appModel.lockService.recordActivity()
    }

    func isStatusItemEvent(_ event: NSEvent) -> Bool {
        statusItems.values.contains { event.window === $0.button?.window }
    }

    func positionDetachablePanel() {
        guard let detachablePanel,
              detachablePanel.isVisible || viewModel.settings.panelPresentationMode == .detachable,
              let screen = statusItems[activeAnchorID]?.button?.window?.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = detachablePanel.frame.size
        let margin: CGFloat = 12
        let origin: NSPoint
        switch viewModel.settings.panelScreenEdge {
        case .left:
            origin = NSPoint(x: visible.minX + margin, y: visible.midY - size.height / 2)
        case .right:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.midY - size.height / 2)
        case .top:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - margin)
        case .bottom:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + margin)
        }
        detachablePanel.setFrameOrigin(origin)
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

    private func ensureDetachablePanel() -> NSPanel {
        if let detachablePanel { return detachablePanel }
        let panel = dependencies.makePanel(appModel)
        detachablePanel = panel
        applyAppearance(viewModel.settings.appearance)
        return panel
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        let name: NSAppearance.Name?
        switch appearance {
        case .system: name = nil
        case .light: name = .aqua
        case .dark: name = .darkAqua
        }
        let resolvedAppearance = name.flatMap { NSAppearance(named: $0) }
        popover.appearance = resolvedAppearance
        detachablePanel?.appearance = resolvedAppearance
    }

    func reanchorPopoverIfNeeded(removesActiveAnchor: Bool) {
        guard removesActiveAnchor,
              popover.isShown,
              popoverAnchor == nil,
              appModel.settings.panelPresentationMode == .popover else { return }
        let destination = appModel.router.activeFeature
        popover.performClose(nil)
        showPopover(
            destination: destination,
            anchorID: activeAnchorID,
            preparesDestination: false
        )
    }

}
