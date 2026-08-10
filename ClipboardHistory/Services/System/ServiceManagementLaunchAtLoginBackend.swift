import ServiceManagement

@MainActor
final class ServiceManagementLaunchAtLoginBackend: LaunchAtLoginBackend {
    static let helperIdentifier = "com.brgirgin.ClipboardHistory.LoginItem"

    private let service: any ServiceManagementAppService
    private let legacyMainAppService: (any ServiceManagementAppService)?

    convenience init() {
        self.init(
            service: SMAppService.loginItem(identifier: Self.helperIdentifier),
            legacyMainAppService: SMAppService.mainApp
        )
    }

    init(
        service: any ServiceManagementAppService,
        legacyMainAppService: (any ServiceManagementAppService)? = nil
    ) {
        self.service = service
        self.legacyMainAppService = legacyMainAppService
    }

    var isEnabled: Bool {
        service.status == .enabled || legacyMainAppService?.status == .enabled
    }

    func migrateLegacyRegistrationIfNeeded() throws {
        guard let legacyMainAppService, legacyMainAppService.status == .enabled else { return }
        if service.status != .enabled { try service.register() }
        try legacyMainAppService.unregister()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if service.status != .enabled { try service.register() }
            if legacyMainAppService?.status == .enabled { try legacyMainAppService?.unregister() }
        } else {
            if service.status == .enabled { try service.unregister() }
            if legacyMainAppService?.status == .enabled { try legacyMainAppService?.unregister() }
        }
    }
}
