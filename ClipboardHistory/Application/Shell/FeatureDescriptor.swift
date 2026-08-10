import Foundation

struct FeatureDescriptor: Identifiable, Equatable, Sendable {
    let id: UtilityFeatureID
    let title: String
    let summary: String
    let systemImage: String
    let supportedClickActions: [FeatureClickAction]
    let defaultClickAction: FeatureClickAction

    func title(for action: FeatureClickAction) -> String {
        guard action == .open else { return action.title }
        return switch id {
        case .clipboard: String(localized: "Open History")
        case .notes: String(localized: "Open Notes")
        case .keyboardCleaning: String(localized: "Open Keyboard Cleaning Controls")
        case .scrollReverse: String(localized: "Open Scroll Reverse Controls")
        case .systemMonitor: String(localized: "Open System Monitor")
        case .audioMixer: String(localized: "Open Audio Mixer")
        }
    }
}
