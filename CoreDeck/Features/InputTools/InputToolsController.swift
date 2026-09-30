import AppKit
import Combine
import Foundation

@MainActor
final class InputToolsController: ObservableObject {
    let keyboardCleaning: KeyboardCleaningController
    let scrollReversal: ScrollReversalController

    private let coordinator: any InputEventTapCoordinating
    private var workspaceCancellables: Set<AnyCancellable> = []

    init(
        coordinator: any InputEventTapCoordinating,
        settings: AppSettings,
        keyboardCleaning: KeyboardCleaningController? = nil,
        scrollReversal: ScrollReversalController? = nil
    ) {
        self.coordinator = coordinator
        self.keyboardCleaning = keyboardCleaning
            ?? KeyboardCleaningController(coordinator: coordinator)
        self.scrollReversal = scrollReversal
            ?? ScrollReversalController(coordinator: coordinator, settings: settings)

        coordinator.interruptionHandler = { [weak self] in
            self?.keyboardCleaning.eventTapDidFail()
            self?.scrollReversal.eventTapDidFail()
        }
        observeWorkspaceLifecycle()
        self.scrollReversal.activatePersistedPreference()
    }

    func prepareForShutdown() {
        keyboardCleaning.stop()
        scrollReversal.suspend()
        coordinator.stopAll()
        workspaceCancellables.removeAll()
    }

    private func observeWorkspaceLifecycle() {
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .sink { [weak self] _ in self?.keyboardCleaning.stop() }
            .store(in: &workspaceCancellables)
        notifications.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.keyboardCleaning.stop() }
            .store(in: &workspaceCancellables)
        notifications.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in self?.scrollReversal.refreshAfterWake() }
            .store(in: &workspaceCancellables)
        notifications.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.scrollReversal.refreshAfterWake() }
            .store(in: &workspaceCancellables)
    }
}
