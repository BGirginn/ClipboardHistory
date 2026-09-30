import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginBackend: AnyObject {
    var isEnabled: Bool { get }
    func migrateLegacyRegistrationIfNeeded() throws
    func setEnabled(_ enabled: Bool) throws
}

extension LaunchAtLoginBackend {
    func migrateLegacyRegistrationIfNeeded() throws {}
}
