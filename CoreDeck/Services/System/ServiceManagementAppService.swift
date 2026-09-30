import ServiceManagement

@MainActor
protocol ServiceManagementAppService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: ServiceManagementAppService {}
