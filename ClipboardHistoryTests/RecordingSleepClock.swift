import Foundation
@testable import ClipboardHistory

actor RecordingSleepClock: SleepClock {
    private var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}
