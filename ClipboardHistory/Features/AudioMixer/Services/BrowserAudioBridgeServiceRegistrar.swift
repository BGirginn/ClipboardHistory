import Foundation
import ServiceManagement

@MainActor
final class BrowserAudioBridgeServiceRegistrar {
    static let plistName = "com.brgirgin.ClipboardHistory.BrowserAudioBridge.plist"

    private let service: any ServiceManagementAppService
    private let registrationAllowed: Bool

    convenience init() {
        self.init(
            service: SMAppService.agent(plistName: Self.plistName),
            registrationAllowed: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )
    }

    init(service: any ServiceManagementAppService, registrationAllowed: Bool = true) {
        self.service = service
        self.registrationAllowed = registrationAllowed
    }

    func registerIfNeeded() -> BrowserAudioBridgeServiceRegistrationResult {
        guard registrationAllowed else { return .ready }
        AppLog.audio.info("Browser audio service registration status: \(String(describing: self.service.status.rawValue), privacy: .public)")
        switch service.status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                AppLog.audio.error("Browser audio service registration failed: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
            AppLog.audio.info("Browser audio service status after registration: \(String(describing: self.service.status.rawValue), privacy: .public)")
            return switch service.status {
            case .enabled: .ready
            case .requiresApproval: .requiresApproval
            case .notFound:
                .failed(String(localized: "Browser audio service is missing from the application bundle."))
            case .notRegistered:
                .failed(String(localized: "Browser audio service could not be registered."))
            @unknown default:
                .failed(String(localized: "Browser audio service returned an unknown status."))
            }
        @unknown default:
            return .failed(String(localized: "Browser audio service returned an unknown status."))
        }
    }
}
