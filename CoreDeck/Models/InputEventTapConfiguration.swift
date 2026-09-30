import Foundation

struct InputEventTapConfiguration: Equatable, Sendable {
    var blocksKeyboard = false
    var scrollReversal = ScrollReversalConfiguration.disabled

    var isEmpty: Bool {
        !blocksKeyboard && !scrollReversal.hasActiveAxis
    }
}
