import Foundation

struct LegacyDefaultsMigrator {
    static let legacyDomain = "com.brgirgin.ClipboardHistory"
    static let currentDomain = "com.brgirgin.CoreDeck"
    private static let completionKey = "CoreDeck.legacyDefaultsMigration.v1"
    private let legacyDomain: String
    private let currentDomain: String

    init(legacyDomain: String = Self.legacyDomain, currentDomain: String = Self.currentDomain) {
        self.legacyDomain = legacyDomain
        self.currentDomain = currentDomain
    }

    func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty else { return }
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[Self.completionKey] as? Bool != true else { return }
        for (key, value) in legacy where current[key] == nil {
            current[key] = value
        }
        current[Self.completionKey] = true
        defaults.setPersistentDomain(current, forName: currentDomain)
    }
}
