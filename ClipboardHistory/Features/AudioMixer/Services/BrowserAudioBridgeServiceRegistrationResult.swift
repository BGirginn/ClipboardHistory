import Foundation

enum BrowserAudioBridgeServiceRegistrationResult: Equatable {
    case ready
    case requiresApproval
    case failed(String)

    var message: String? {
        switch self {
        case .ready:
            nil
        case .requiresApproval:
            String(
                localized: "Allow ClipboardHistory Browser Audio in System Settings > General > Login Items & Extensions."
            )
        case let .failed(message):
            message
        }
    }
}
