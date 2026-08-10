import Foundation

enum AudioMixerPermissionState: Equatable, Sendable {
    case notRequested
    case ready
    case denied
    case failed(String)

    var message: String? {
        switch self {
        case .notRequested:
            String(localized: "Change an app's volume to request System Audio Recording permission.")
        case .ready:
            nil
        case .denied:
            String(localized: "System Audio Recording permission is required.")
        case let .failed(message):
            message
        }
    }
}
