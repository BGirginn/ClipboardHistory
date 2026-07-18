import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var globalShortcutEnabled: Bool { didSet { save() } }
    @Published var closePanelAfterCopying: Bool { didSet { save() } }
    @Published var historyLimit: Int { didSet { save() } }
    @Published var thumbnailCacheMegabytes: Int { didSet { save() } }
    @Published var selectedFilter: ClipboardFilter { didSet { save() } }
    @Published var selectedSortMode: ClipboardSortMode { didSet { save() } }
    @Published var sensitiveStoragePolicy: SensitiveStoragePolicy { didSet { save() } }
    @Published var sensitiveRetentionSeconds: Int { didSet { save() } }
    @Published var excludedBundleIdentifiersText: String { didSet { save() } }
    @Published var allowedBundleIdentifiersText: String { didSet { save() } }
    @Published var encryptionMode: EncryptionMode { didSet { save() } }
    @Published var autoLockOption: AutoLockOption { didSet { save() } }
    @Published var retentionDays: Int { didSet { save() } }
    @Published var imageRetentionDays: Int { didSet { save() } }
    @Published var maximumStorageMegabytes: Int { didSet { save() } }
    @Published var duplicateDetectionScope: DuplicateDetectionScope { didSet { save() } }
    @Published var secretDetectionEnabled: Bool { didSet { save() } }
    @Published var privateModeDefaultEnabled: Bool { didSet { save() } }
    @Published var launchAtLoginRequested: Bool { didSet { save() } }
    @Published var captureRichText: Bool { didSet { save() } }
    @Published var capturePDFs: Bool { didSet { save() } }
    @Published var captureFiles: Bool { didSet { save() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        globalShortcutEnabled = defaults.object(forKey: Key.globalShortcutEnabled) as? Bool ?? true
        closePanelAfterCopying = defaults.object(forKey: Key.closePanelAfterCopying) as? Bool ?? true
        historyLimit = max(10, defaults.integer(forKey: Key.historyLimit).nonzero(or: 100))
        thumbnailCacheMegabytes = max(
            8,
            defaults.integer(forKey: Key.thumbnailCacheMegabytes).nonzero(or: 64)
        )
        selectedFilter = ClipboardFilter(
            rawValue: defaults.string(forKey: Key.selectedFilter) ?? ""
        ) ?? .all
        selectedSortMode = ClipboardSortMode(
            rawValue: defaults.string(forKey: Key.selectedSortMode) ?? ""
        ) ?? .newestFirst
        sensitiveStoragePolicy = SensitiveStoragePolicy(
            rawValue: defaults.string(forKey: Key.sensitiveStoragePolicy) ?? ""
        ) ?? .neverSave
        sensitiveRetentionSeconds = max(
            10,
            defaults.integer(forKey: Key.sensitiveRetentionSeconds).nonzero(or: 60)
        )
        excludedBundleIdentifiersText = defaults.string(forKey: Key.excludedBundleIdentifiersText)
            ?? Self.suggestedExcludedApplications
        allowedBundleIdentifiersText = defaults.string(forKey: Key.allowedBundleIdentifiersText) ?? ""
        encryptionMode = EncryptionMode(
            rawValue: defaults.string(forKey: Key.encryptionMode) ?? ""
        ) ?? .sensitive
        autoLockOption = AutoLockOption(
            rawValue: defaults.string(forKey: Key.autoLockOption) ?? ""
        ) ?? .never
        retentionDays = max(1, defaults.integer(forKey: Key.retentionDays).nonzero(or: 90))
        imageRetentionDays = max(
            1,
            defaults.integer(forKey: Key.imageRetentionDays).nonzero(or: 14)
        )
        maximumStorageMegabytes = max(
            50,
            defaults.integer(forKey: Key.maximumStorageMegabytes).nonzero(or: 2_048)
        )
        duplicateDetectionScope = DuplicateDetectionScope(
            rawValue: defaults.string(forKey: Key.duplicateDetectionScope) ?? ""
        ) ?? .lastTen
        secretDetectionEnabled = defaults.object(forKey: Key.secretDetectionEnabled) as? Bool ?? true
        privateModeDefaultEnabled = defaults.object(forKey: Key.privateModeDefaultEnabled) as? Bool ?? false
        launchAtLoginRequested = defaults.object(forKey: Key.launchAtLoginRequested) as? Bool ?? false
        captureRichText = defaults.object(forKey: Key.captureRichText) as? Bool ?? true
        capturePDFs = defaults.object(forKey: Key.capturePDFs) as? Bool ?? true
        captureFiles = defaults.object(forKey: Key.captureFiles) as? Bool ?? true
    }

    var excludedBundleIdentifiers: Set<String> {
        parseBundleIdentifiers(excludedBundleIdentifiersText)
    }

    var allowedBundleIdentifiers: Set<String> {
        parseBundleIdentifiers(allowedBundleIdentifiersText)
    }

    private func parseBundleIdentifiers(_ value: String) -> Set<String> {
        Set(
            value.split { character in
                character.isWhitespace || character == "," || character == ";"
            }.map { $0.lowercased() }
        )
    }

    private func save() {
        defaults.set(globalShortcutEnabled, forKey: Key.globalShortcutEnabled)
        defaults.set(closePanelAfterCopying, forKey: Key.closePanelAfterCopying)
        defaults.set(historyLimit, forKey: Key.historyLimit)
        defaults.set(thumbnailCacheMegabytes, forKey: Key.thumbnailCacheMegabytes)
        defaults.set(selectedFilter.rawValue, forKey: Key.selectedFilter)
        defaults.set(selectedSortMode.rawValue, forKey: Key.selectedSortMode)
        defaults.set(sensitiveStoragePolicy.rawValue, forKey: Key.sensitiveStoragePolicy)
        defaults.set(sensitiveRetentionSeconds, forKey: Key.sensitiveRetentionSeconds)
        defaults.set(excludedBundleIdentifiersText, forKey: Key.excludedBundleIdentifiersText)
        defaults.set(allowedBundleIdentifiersText, forKey: Key.allowedBundleIdentifiersText)
        defaults.set(encryptionMode.rawValue, forKey: Key.encryptionMode)
        defaults.set(autoLockOption.rawValue, forKey: Key.autoLockOption)
        defaults.set(retentionDays, forKey: Key.retentionDays)
        defaults.set(imageRetentionDays, forKey: Key.imageRetentionDays)
        defaults.set(maximumStorageMegabytes, forKey: Key.maximumStorageMegabytes)
        defaults.set(duplicateDetectionScope.rawValue, forKey: Key.duplicateDetectionScope)
        defaults.set(secretDetectionEnabled, forKey: Key.secretDetectionEnabled)
        defaults.set(privateModeDefaultEnabled, forKey: Key.privateModeDefaultEnabled)
        defaults.set(launchAtLoginRequested, forKey: Key.launchAtLoginRequested)
        defaults.set(captureRichText, forKey: Key.captureRichText)
        defaults.set(capturePDFs, forKey: Key.capturePDFs)
        defaults.set(captureFiles, forKey: Key.captureFiles)
    }

    private static let suggestedExcludedApplications = """
    com.1password.1password
    com.agilebits.onepassword7
    com.bitwarden.desktop
    com.dashlane.Dashlane
    com.lastpass.LastPass
    com.apple.keychainaccess
    """

    private enum Key {
        static let globalShortcutEnabled = "globalShortcutEnabled"
        static let closePanelAfterCopying = "closePanelAfterCopying"
        static let historyLimit = "historyLimit"
        static let thumbnailCacheMegabytes = "thumbnailCacheMegabytes"
        static let selectedFilter = "selectedFilter"
        static let selectedSortMode = "selectedSortMode"
        static let sensitiveStoragePolicy = "sensitiveStoragePolicy"
        static let sensitiveRetentionSeconds = "sensitiveRetentionSeconds"
        static let excludedBundleIdentifiersText = "excludedBundleIdentifiersText"
        static let allowedBundleIdentifiersText = "allowedBundleIdentifiersText"
        static let encryptionMode = "encryptionMode"
        static let autoLockOption = "autoLockOption"
        static let retentionDays = "retentionDays"
        static let imageRetentionDays = "imageRetentionDays"
        static let maximumStorageMegabytes = "maximumStorageMegabytes"
        static let duplicateDetectionScope = "duplicateDetectionScope"
        static let secretDetectionEnabled = "secretDetectionEnabled"
        static let privateModeDefaultEnabled = "privateModeDefaultEnabled"
        static let launchAtLoginRequested = "launchAtLoginRequested"
        static let captureRichText = "captureRichText"
        static let capturePDFs = "capturePDFs"
        static let captureFiles = "captureFiles"
    }
}

private extension Int {
    func nonzero(or fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
