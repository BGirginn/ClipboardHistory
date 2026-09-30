import Foundation

struct FeaturePlacement: Codable, Equatable, Sendable {
    var showsInControlCenter: Bool
    var menuBarVisibility: MenuBarVisibilityPolicy
    var showsInDrawer: Bool

    var showsInTopBar: Bool {
        menuBarVisibility != .hidden && !showsInDrawer
    }

    var showsStandaloneItem: Bool {
        get { menuBarVisibility != .hidden }
        set { menuBarVisibility = newValue ? .always : .hidden }
    }

    init(
        showsInControlCenter: Bool,
        menuBarVisibility: MenuBarVisibilityPolicy,
        showsInDrawer: Bool = false
    ) {
        self.showsInControlCenter = showsInControlCenter
        self.menuBarVisibility = menuBarVisibility
        self.showsInDrawer = showsInDrawer
    }

    init(
        showsInControlCenter: Bool,
        showsStandaloneItem: Bool
    ) {
        self.init(
            showsInControlCenter: showsInControlCenter,
            menuBarVisibility: showsStandaloneItem ? .always : .hidden
        )
    }

    private enum CodingKeys: String, CodingKey {
        case showsInControlCenter
        case menuBarVisibility
        case showsStandaloneItem
        case showsInDrawer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsInControlCenter = try container.decode(Bool.self, forKey: .showsInControlCenter)
        showsInDrawer = try container.decodeIfPresent(Bool.self, forKey: .showsInDrawer) ?? false
        if let policy = try container.decodeIfPresent(
            MenuBarVisibilityPolicy.self,
            forKey: .menuBarVisibility
        ) {
            menuBarVisibility = policy
        } else {
            let legacyValue = try container.decodeIfPresent(
                Bool.self,
                forKey: .showsStandaloneItem
            ) ?? false
            menuBarVisibility = legacyValue ? .always : .hidden
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsInControlCenter, forKey: .showsInControlCenter)
        try container.encode(menuBarVisibility, forKey: .menuBarVisibility)
        try container.encode(showsInDrawer, forKey: .showsInDrawer)
    }
}
