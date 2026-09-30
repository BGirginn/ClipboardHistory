import Combine
import Foundation

@MainActor
final class KeyboardCleaningController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var permissionRequired = false
    @Published private(set) var errorMessage: String?

    private let coordinator: any InputEventTapCoordinating
    private let timerScheduler: any RepeatingTimerScheduling
    private var timer: (any RepeatingTimerToken)?

    init(
        coordinator: any InputEventTapCoordinating = SystemInputEventTapCoordinator(),
        timerScheduler: any RepeatingTimerScheduling = SystemRepeatingTimerScheduler()
    ) {
        self.coordinator = coordinator
        self.timerScheduler = timerScheduler
    }

    func start() {
        guard !isActive else { return }
        permissionRequired = false
        errorMessage = nil

        guard coordinator.isTrusted || coordinator.requestAccessibilityAccess() else {
            permissionRequired = true
            return
        }
        guard coordinator.setKeyboardBlocking(true) else {
            errorMessage = String(localized: "Keyboard input could not be blocked. Grant Accessibility permission, then try again.")
            return
        }

        isActive = true
        timer?.cancel()
        timer = timerScheduler.schedule(interval: 1, tolerance: 0.1) { [weak self] in
            self?.checkEventTapHealth()
        }
    }

    func toggle() {
        isActive ? stop() : start()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if isActive { isActive = false }
        _ = coordinator.setKeyboardBlocking(false)
    }

    func retryAfterPermissionChange() {
        start()
    }

    func openAccessibilitySettings() {
        coordinator.openAccessibilitySettings()
    }

    private func checkEventTapHealth() {
        guard isActive else { return }
        guard coordinator.maintain() else {
            stop()
            errorMessage = String(localized: "Keyboard input blocking stopped unexpectedly. Start Keyboard Cleaning Mode again.")
            return
        }
    }

    func eventTapDidFail() {
        guard isActive else { return }
        timer?.cancel()
        timer = nil
        isActive = false
        _ = coordinator.setKeyboardBlocking(false)
        errorMessage = String(
            localized: "Keyboard input blocking stopped unexpectedly. Start Keyboard Cleaning Mode again."
        )
    }

    deinit {
        timer?.cancel()
    }
}
