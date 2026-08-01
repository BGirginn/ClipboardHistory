import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginBackend: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
protocol ServiceManagementAppService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: ServiceManagementAppService {}

@MainActor
final class ServiceManagementLaunchAtLoginBackend: LaunchAtLoginBackend {
    private let service: any ServiceManagementAppService

    init(service: any ServiceManagementAppService = SMAppService.mainApp) {
        self.service = service
    }

    var isEnabled: Bool { service.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
