import Foundation

struct DrawerItemObservation: Codable, Equatable, Sendable {
    let id: ManagedMenuBarItemID
    let capabilities: DrawerItemCapabilities
    let placement: DrawerPlacement
    let screenIdentifier: String
    let leadingAnchorID: ManagedMenuBarItemID?
    let trailingAnchorID: ManagedMenuBarItemID?
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func matchesTopology(of other: Self, tolerance: Double = 2) -> Bool {
        id == other.id
            && screenIdentifier == other.screenIdentifier
            && leadingAnchorID == other.leadingAnchorID
            && trailingAnchorID == other.trailingAnchorID
            && abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
