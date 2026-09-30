import Foundation

enum NetworkInterfaceScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case primaryWiFi
    case allPhysical

    var id: Self { self }

    var title: String {
        switch self {
        case .primaryWiFi: String(localized: "Active network interface")
        case .allPhysical: String(localized: "All physical network interfaces")
        }
    }
}
