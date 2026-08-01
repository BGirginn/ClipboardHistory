import Foundation

protocol RepeatingTimerToken: AnyObject, Sendable {
    func cancel()
}

@MainActor
protocol RepeatingTimerScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any RepeatingTimerToken
}

@MainActor
final class SystemRepeatingTimerScheduler: RepeatingTimerScheduling {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any RepeatingTimerToken {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        return SystemRepeatingTimerToken(timer: timer)
    }
}

private final class SystemRepeatingTimerToken: RepeatingTimerToken, @unchecked Sendable {
    private nonisolated(unsafe) var timer: Timer?

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
