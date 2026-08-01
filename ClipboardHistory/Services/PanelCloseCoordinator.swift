import AppKit

@MainActor
protocol PanelEventMonitoring: AnyObject {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any?
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func removeMonitor(_ monitor: Any)
}

@MainActor
final class PanelCloseCoordinator {
    private let notificationCenter: NotificationCenter
    private let isPanelShown: () -> Bool
    private let isPanelEvent: (NSEvent) -> Bool
    private let isStatusItemEvent: (NSEvent) -> Bool
    private let closePanel: () -> Void
    private let eventMonitor: any PanelEventMonitoring

    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var deferredCloseTask: Task<Void, Never>?
    private var isStarted = false
    private(set) var menuTrackingDepth = 0
    private(set) var hasDeferredClose = false
    private(set) var menuCommandWasSelected = false

    init(
        notificationCenter: NotificationCenter = .default,
        eventMonitor: any PanelEventMonitoring = SystemPanelEventMonitor(),
        isPanelShown: @escaping () -> Bool,
        isPanelEvent: @escaping (NSEvent) -> Bool = { _ in false },
        isStatusItemEvent: @escaping (NSEvent) -> Bool = { _ in false },
        closePanel: @escaping () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.eventMonitor = eventMonitor
        self.isPanelShown = isPanelShown
        self.isPanelEvent = isPanelEvent
        self.isStatusItemEvent = isStatusItemEvent
        self.closePanel = closePanel
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidBeginTracking),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

        globalEventMonitor = eventMonitor.addGlobalMonitor { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestCloseForOutsideInteraction()
            }
        }
        localEventMonitor = eventMonitor.addLocalMonitor { [weak self] event in
            let shouldRequestClose: Bool = MainActor.assumeIsolated {
                guard let self,
                      !self.isPanelEvent(event),
                      !self.isStatusItemEvent(event) else {
                    return false
                }
                return true
            }
            if shouldRequestClose {
                MainActor.assumeIsolated { [weak self] in
                    self?.requestCloseForOutsideInteraction()
                }
            }
            return event
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        notificationCenter.removeObserver(self)
        if let globalEventMonitor {
            eventMonitor.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            eventMonitor.removeMonitor(localEventMonitor)
        }
        globalEventMonitor = nil
        localEventMonitor = nil
        resetMenuTrackingState()
    }

    func requestCloseForOutsideInteraction() {
        guard isPanelShown() else { return }
        if menuTrackingDepth > 0 {
            hasDeferredClose = true
        } else {
            deferredCloseTask?.cancel()
            deferredCloseTask = nil
            closePanel()
        }
    }

    func menuTrackingDidBegin() {
        guard isPanelShown() else { return }
        if menuTrackingDepth == 0 {
            deferredCloseTask?.cancel()
            deferredCloseTask = nil
            hasDeferredClose = false
            menuCommandWasSelected = false
        }
        menuTrackingDepth += 1
    }

    func menuTrackingDidEnd() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }

        guard hasDeferredClose, !menuCommandWasSelected, isPanelShown() else {
            resetMenuTrackingState()
            return
        }

        hasDeferredClose = false
        deferredCloseTask?.cancel()
        deferredCloseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self else { return }
            deferredCloseTask = nil
            guard !menuCommandWasSelected, isPanelShown() else {
                menuCommandWasSelected = false
                return
            }
            menuCommandWasSelected = false
            closePanel()
        }
    }

    func menuCommandDidRun() {
        guard menuTrackingDepth > 0 || deferredCloseTask != nil else { return }
        menuCommandWasSelected = true
        hasDeferredClose = false
        deferredCloseTask?.cancel()
        deferredCloseTask = nil
    }

    @objc private func applicationDidResignActive() {
        requestCloseForOutsideInteraction()
    }

    @objc private func menuDidBeginTracking() {
        menuTrackingDidBegin()
    }

    @objc private func menuDidEndTracking() {
        menuTrackingDidEnd()
    }

    private func resetMenuTrackingState() {
        deferredCloseTask?.cancel()
        deferredCloseTask = nil
        menuTrackingDepth = 0
        hasDeferredClose = false
        menuCommandWasSelected = false
    }

}
