import Foundation
import Security

struct BrowserAudioBridgeClientValidator {
    private static let allowedBundleIdentifiers: Set<String> = [
        "com.brgirgin.ClipboardHistory",
        "com.brgirgin.ClipboardHistory.LoginItem",
        "com.brgirgin.ClipboardHistory.SafariExtension"
    ]

    func validatedBundleIdentifier(for connection: NSXPCConnection) -> String? {
        guard connection.effectiveUserIdentifier == getuid(),
              let guest = guestCode(processIdentifier: connection.processIdentifier),
              SecCodeCheckValidity(guest, [], nil) == errSecSuccess,
              let guestInfo = signingInformation(for: guest),
              let identifier = guestInfo[kSecCodeInfoIdentifier as String] as? String,
              Self.allowedBundleIdentifiers.contains(identifier),
              let guestCertificate = leafCertificateData(from: guestInfo),
              let ownCode = ownCode(),
              let ownInfo = signingInformation(for: ownCode),
              let ownCertificate = leafCertificateData(from: ownInfo),
              guestCertificate == ownCertificate else { return nil }
        return identifier
    }

    private func guestCode(processIdentifier: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else {
            return nil
        }
        return code
    }

    private func ownCode() -> SecCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess else { return nil }
        return code
    }

    private func signingInformation(for code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess else { return nil }
        return information as? [String: Any]
    }

    private func leafCertificateData(from information: [String: Any]) -> Data? {
        guard let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return SecCertificateCopyData(leaf) as Data
    }
}
