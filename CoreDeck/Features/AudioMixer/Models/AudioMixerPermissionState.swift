import Foundation

enum AudioMixerPermissionState: Equatable, Sendable {
    case notRequested
    case requesting
    case ready
    case denied
    case failed(String)

    var message: String? {
        switch self {
        case .notRequested:
            String(localized: "Change an app's volume to request System Audio Recording permission.")
        case .requesting:
            String(localized: "Requesting System Audio Recording access…")
        case .ready:
            nil
        case .denied:
            String(localized: "System Audio Recording permission is required.")
        case let .failed(message):
            message
        }
    }
}
