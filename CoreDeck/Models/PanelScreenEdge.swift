import Foundation

enum PanelScreenEdge: String, CaseIterable, Identifiable, Sendable {
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        case .top: String(localized: "Top")
        case .bottom: String(localized: "Bottom")
        }
    }
}
