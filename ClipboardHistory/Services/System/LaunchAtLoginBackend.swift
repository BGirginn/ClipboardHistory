import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginBackend: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
