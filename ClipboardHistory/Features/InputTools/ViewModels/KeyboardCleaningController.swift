import Combine
import Foundation

@MainActor
final class KeyboardCleaningController: ObservableObject {
    static let defaultDuration: TimeInterval = 60

    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = Int(defaultDuration)
    @Published private(set) var permissionRequired = false
    @Published private(set) var errorMessage: String?

    private let coordinator: any InputEventTapCoordinating
    private let timerScheduler: any RepeatingTimerScheduling
    private let duration: TimeInterval
    private let now: () -> Date
    private var endDate: Date?
    private var timer: (any RepeatingTimerToken)?

    init(
        coordinator: any InputEventTapCoordinating = SystemInputEventTapCoordinator(),
        timerScheduler: any RepeatingTimerScheduling = SystemRepeatingTimerScheduler(),
        duration: TimeInterval = defaultDuration,
        now: @escaping () -> Date = { .now }
    ) {
        self.coordinator = coordinator
        self.timerScheduler = timerScheduler
        self.duration = max(1, duration)
        self.now = now
        remainingSeconds = Int(self.duration.rounded(.up))
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

        let endDate = now().addingTimeInterval(duration)
        self.endDate = endDate
        remainingSeconds = Int(duration.rounded(.up))
        isActive = true
        timer?.cancel()
        timer = timerScheduler.schedule(interval: 1, tolerance: 0.1) { [weak self] in
            self?.updateCountdown()
        }
    }

    func stop() {
        guard isActive || timer != nil || endDate != nil else { return }
        timer?.cancel()
        timer = nil
        endDate = nil
        isActive = false
        _ = coordinator.setKeyboardBlocking(false)
        remainingSeconds = Int(duration.rounded(.up))
    }

    func retryAfterPermissionChange() {
        start()
    }

    func openAccessibilitySettings() {
        coordinator.openAccessibilitySettings()
    }

    private func updateCountdown() {
        guard isActive, let endDate else { return }
        guard coordinator.maintain() else {
            stop()
            errorMessage = String(localized: "Keyboard input blocking stopped unexpectedly. Start Keyboard Cleaning Mode again.")
            return
        }
        let remaining = max(0, endDate.timeIntervalSince(now()))
        remainingSeconds = Int(remaining.rounded(.up))
        if remainingSeconds == 0 {
            stop()
        }
    }

    func eventTapDidFail() {
        guard isActive else { return }
        timer?.cancel()
        timer = nil
        endDate = nil
        isActive = false
        remainingSeconds = Int(duration.rounded(.up))
        errorMessage = String(
            localized: "Keyboard input blocking stopped unexpectedly. Start Keyboard Cleaning Mode again."
        )
    }

    deinit {
        timer?.cancel()
    }
}
