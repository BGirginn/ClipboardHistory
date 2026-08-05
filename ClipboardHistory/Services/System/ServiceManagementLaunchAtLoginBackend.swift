import ServiceManagement

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
