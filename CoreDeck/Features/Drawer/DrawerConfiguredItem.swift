import Foundation

struct DrawerConfiguredItem: Codable, Equatable, Identifiable, Sendable {
    var id: ManagedMenuBarItemID
    var desiredPlacement: DrawerPlacement
}
