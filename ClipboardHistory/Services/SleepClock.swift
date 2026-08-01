import Foundation

protocol SleepClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct SystemSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
