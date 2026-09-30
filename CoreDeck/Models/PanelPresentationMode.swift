import Foundation

enum PanelPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case popover
    case detachable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popover: String(localized: "Menu Bar Popover")
        case .detachable: String(localized: "Detachable Keyboard Panel")
        }
    }
}
