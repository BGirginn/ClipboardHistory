import Foundation

@MainActor
protocol RepeatingTimerScheduling: AnyObject {
    func schedule(
        interval: TimeInterval,
        tolerance: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any RepeatingTimerToken
}
