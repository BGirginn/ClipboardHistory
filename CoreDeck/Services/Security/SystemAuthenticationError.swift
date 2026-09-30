import Foundation

enum SystemAuthenticationError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        }
    }
}
