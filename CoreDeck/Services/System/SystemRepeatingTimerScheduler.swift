import Foundation

@MainActor
final class SystemRepeatingTimerScheduler: RepeatingTimerScheduling {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any RepeatingTimerToken {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        // Clipboard capture and event-tap health checks must keep advancing while AppKit
        // temporarily switches the main run loop into menu or event-tracking modes.
        RunLoop.main.add(timer, forMode: .common)
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
