import Foundation

struct ScrollReversalConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var reversesDiscreteVertical: Bool
    var reversesDiscreteHorizontal: Bool
    var reversesPreciseVertical: Bool
    var reversesPreciseHorizontal: Bool

    static let disabled = ScrollReversalConfiguration(
        isEnabled: false,
        reversesDiscreteVertical: true,
        reversesDiscreteHorizontal: true,
        reversesPreciseVertical: false,
        reversesPreciseHorizontal: false
    )

    var hasActiveAxis: Bool {
        isEnabled && (
            reversesDiscreteVertical
                || reversesDiscreteHorizontal
                || reversesPreciseVertical
                || reversesPreciseHorizontal
        )
    }

    func reversesVertical(isContinuous: Bool) -> Bool {
        guard isEnabled else { return false }
        return isContinuous ? reversesPreciseVertical : reversesDiscreteVertical
    }

    func reversesHorizontal(isContinuous: Bool) -> Bool {
        guard isEnabled else { return false }
        return isContinuous ? reversesPreciseHorizontal : reversesDiscreteHorizontal
    }
}
