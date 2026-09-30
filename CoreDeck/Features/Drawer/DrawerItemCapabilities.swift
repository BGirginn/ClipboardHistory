import Foundation

struct DrawerItemCapabilities: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    static let discover = Self(rawValue: 1 << 0)
    static let move = Self(rawValue: 1 << 1)
    static let reclaimSpace = Self(rawValue: 1 << 2)
    static let activate = Self(rawValue: 1 << 3)
    static let observe = Self(rawValue: 1 << 4)
    static let restore = Self(rawValue: 1 << 5)

    static let externallyManaged: Self = [
        .discover, .move, .reclaimSpace, .activate, .observe, .restore
    ]
}
