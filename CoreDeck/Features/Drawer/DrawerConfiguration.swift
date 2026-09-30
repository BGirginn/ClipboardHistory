import Foundation

struct DrawerConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var externalManagementEnabled: Bool
    var items: [DrawerConfiguredItem]

    static let defaults = Self(
        version: currentVersion,
        externalManagementEnabled: false,
        items: []
    )

    mutating func setPlacement(_ placement: DrawerPlacement, for id: ManagedMenuBarItemID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].desiredPlacement = placement
        } else {
            items.append(DrawerConfiguredItem(id: id, desiredPlacement: placement))
        }
        items.sort { $0.id.persistenceKey < $1.id.persistenceKey }
    }
}
