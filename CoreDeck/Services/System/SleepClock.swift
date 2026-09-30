import Foundation

protocol SleepClock: Sendable {
    func sleep(for duration: Duration) async throws
}
