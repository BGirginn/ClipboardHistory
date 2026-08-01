import Foundation

enum KeychainBackend: String, Sendable {
    case dataProtection
    case login

    var service: String {
        switch self {
        case .dataProtection:
            "com.brgirgin.ClipboardHistory.encryption"
        case .login:
            "com.brgirgin.ClipboardHistory.community.encryption"
        }
    }

    var usesDataProtectionKeychain: Bool {
        self == .dataProtection
    }
}
