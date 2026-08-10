import Foundation

enum UtilityFeatureID: String, CaseIterable, Codable, Identifiable, Sendable {
    case clipboard
    case notes
    case keyboardCleaning
    case scrollReverse
    case systemMonitor
    case audioMixer

    var id: String { rawValue }
}
