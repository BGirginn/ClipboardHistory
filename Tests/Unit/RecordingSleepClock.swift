import Foundation
@testable import ClipboardHistoryTestHost

actor RecordingSleepClock: SleepClock {
    private var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}
