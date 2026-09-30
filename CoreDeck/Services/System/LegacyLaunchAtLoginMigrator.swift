import Foundation

@MainActor
struct LegacyLaunchAtLoginMigrator {
    private static let completionKey = "CoreDeck.legacyLoginItemMigration.v1"
    private let legacyDomain: String
    private let currentDomain: String

    init(
        legacyDomain: String = LegacyDefaultsMigrator.legacyDomain,
        currentDomain: String = LegacyDefaultsMigrator.currentDomain
    ) {
        self.legacyDomain = legacyDomain
        self.currentDomain = currentDomain
    }

    func migrateIfNeeded(service: LaunchAtLoginService, defaults: UserDefaults = .standard) {
        guard let legacy = defaults.persistentDomain(forName: legacyDomain),
              legacy["launchAtLoginRequested"] as? Bool == true else { return }
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[Self.completionKey] as? Bool != true else { return }
        if !service.isEnabled {
            service.setEnabled(true)
            guard service.isEnabled else { return }
        }
        current[Self.completionKey] = true
        defaults.setPersistentDomain(current, forName: currentDomain)
    }
}
