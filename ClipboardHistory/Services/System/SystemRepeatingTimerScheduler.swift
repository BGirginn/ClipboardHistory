import Foundation

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
        return Token(timer: timer)
    }

    private final class Token: RepeatingTimerToken, @unchecked Sendable {
        private nonisolated(unsafe) var timer: Timer?

        init(timer: Timer) {
            self.timer = timer
        }

        func cancel() {
            timer?.invalidate()
            timer = nil
        }
    }
}
