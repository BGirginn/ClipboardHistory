import Foundation

struct SystemSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
