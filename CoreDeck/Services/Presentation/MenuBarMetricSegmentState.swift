import CoreGraphics
import Foundation

struct MenuBarMetricSegmentState: Equatable {
    let metric: MenuBarMetricID
    let symbol: String?
    let leadingText: String?
    let value: String
    let accessibilityLabel: String
    let width: CGFloat

    init(
        metric: MenuBarMetricID,
        symbol: String?,
        leadingText: String? = nil,
        value: String,
        accessibilityLabel: String,
        width: CGFloat
    ) {
        self.metric = metric
        self.symbol = symbol
        self.leadingText = leadingText
        self.value = value
        self.accessibilityLabel = accessibilityLabel
        self.width = width
    }
}
