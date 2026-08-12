import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var globalShortcutEnabled: Bool { didSet { save() } }
    @Published var closePanelAfterCopying: Bool { didSet { save() } }
    @Published var appearance: AppAppearance { didSet { save() } }
    @Published var historyLimit: Int { didSet { save() } }
    @Published var thumbnailCacheMegabytes: Int { didSet { save() } }
    @Published var selectedFilter: ClipboardFilter { didSet { save() } }
    @Published var selectedSortMode: ClipboardSortMode { didSet { save() } }
    @Published var sensitiveStoragePolicy: SensitiveStoragePolicy { didSet { save() } }
    @Published var sensitiveRetentionSeconds: Int { didSet { save() } }
    @Published var excludedBundleIdentifiersText: String { didSet { save() } }
    @Published var allowedBundleIdentifiersText: String { didSet { save() } }
    @Published var autoLockOption: AutoLockOption { didSet { save() } }
    @Published private(set) var applicationLockEnabled: Bool { didSet { save() } }
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
    @Published var imageTextRecognitionEnabled: Bool { didSet { save() } }
    @Published var ignoreUniversalClipboard: Bool { didSet { save() } }
    @Published var ignoredPasteboardTypesText: String { didSet { save() } }
    @Published var pasteStackOrder: PasteStackOrder { didSet { save() } }
    @Published var pasteStackRemovesUsedItems: Bool { didSet { save() } }
    @Published var pasteStackTimeoutMinutes: Int { didSet { save() } }
    @Published var globalShortcutPresetID: String { didSet { save() } }
    @Published var shortcutActivationMode: ShortcutActivationMode { didSet { save() } }
    @Published var panelPresentationMode: PanelPresentationMode { didSet { save() } }
    @Published var panelScreenEdge: PanelScreenEdge { didSet { save() } }
    @Published var scrollReversalEnabled: Bool { didSet { save() } }
    @Published var reverseDiscreteScrollVertical: Bool { didSet { save() } }
    @Published var reverseDiscreteScrollHorizontal: Bool { didSet { save() } }
    @Published var reversePreciseScrollVertical: Bool { didSet { save() } }
    @Published var reversePreciseScrollHorizontal: Bool { didSet { save() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        globalShortcutEnabled = defaults.object(forKey: Key.globalShortcutEnabled) as? Bool ?? true
        if defaults.integer(forKey: Key.closePanelAfterCopyingMigrationVersion)
            < Self.closePanelAfterCopyingMigrationVersion {
            closePanelAfterCopying = false
            defaults.set(false, forKey: Key.closePanelAfterCopying)
            defaults.set(
                Self.closePanelAfterCopyingMigrationVersion,
                forKey: Key.closePanelAfterCopyingMigrationVersion
            )
        } else {
            closePanelAfterCopying = defaults.object(forKey: Key.closePanelAfterCopying) as? Bool ?? false
        }
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
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
        defaults.removeObject(forKey: Key.encryptionMode)
        let storedAutoLockOption = AutoLockOption(
            rawValue: defaults.string(forKey: Key.autoLockOption) ?? ""
        ) ?? .never
        autoLockOption = storedAutoLockOption
        if defaults.integer(forKey: Key.applicationLockMigrationVersion) < 1 {
            let migratedLockEnabled = storedAutoLockOption != .never
            applicationLockEnabled = migratedLockEnabled
            defaults.set(migratedLockEnabled, forKey: Key.applicationLockEnabled)
        } else {
            applicationLockEnabled = defaults.object(
                forKey: Key.applicationLockEnabled
            ) as? Bool ?? false
        }
        defaults.removeObject(forKey: Key.captureWhileLocked)
        defaults.set(
            Self.applicationLockMigrationVersion,
            forKey: Key.applicationLockMigrationVersion
        )
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
        imageTextRecognitionEnabled = defaults.object(
            forKey: Key.imageTextRecognitionEnabled
        ) as? Bool ?? true
        ignoreUniversalClipboard = defaults.object(
            forKey: Key.ignoreUniversalClipboard
        ) as? Bool ?? false
        ignoredPasteboardTypesText = defaults.string(
            forKey: Key.ignoredPasteboardTypesText
        ) ?? ""
        pasteStackOrder = PasteStackOrder(
            rawValue: defaults.string(forKey: Key.pasteStackOrder) ?? ""
        ) ?? .fifo
        pasteStackRemovesUsedItems = defaults.object(
            forKey: Key.pasteStackRemovesUsedItems
        ) as? Bool ?? true
        pasteStackTimeoutMinutes = max(
            0,
            defaults.integer(forKey: Key.pasteStackTimeoutMinutes)
        )
        globalShortcutPresetID = defaults.string(forKey: Key.globalShortcutPresetID)
            ?? GlobalShortcut.defaultShortcut.id
        shortcutActivationMode = ShortcutActivationMode(
            rawValue: defaults.string(forKey: Key.shortcutActivationMode) ?? ""
        ) ?? .toggle
        panelPresentationMode = PanelPresentationMode(
            rawValue: defaults.string(forKey: Key.panelPresentationMode) ?? ""
        ) ?? .popover
        panelScreenEdge = PanelScreenEdge(
            rawValue: defaults.string(forKey: Key.panelScreenEdge) ?? ""
        ) ?? .right
        scrollReversalEnabled = defaults.object(
            forKey: Key.scrollReversalEnabled
        ) as? Bool ?? false
        reverseDiscreteScrollVertical = defaults.object(
            forKey: Key.reverseDiscreteScrollVertical
        ) as? Bool ?? true
        reverseDiscreteScrollHorizontal = defaults.object(
            forKey: Key.reverseDiscreteScrollHorizontal
        ) as? Bool ?? true
        reversePreciseScrollVertical = defaults.object(
            forKey: Key.reversePreciseScrollVertical
        ) as? Bool ?? false
        reversePreciseScrollHorizontal = defaults.object(
            forKey: Key.reversePreciseScrollHorizontal
        ) as? Bool ?? false
    }

    var excludedBundleIdentifiers: Set<String> {
        parseBundleIdentifiers(excludedBundleIdentifiersText)
    }

    var allowedBundleIdentifiers: Set<String> {
        parseBundleIdentifiers(allowedBundleIdentifiersText)
    }

    var ignoredPasteboardTypes: Set<String> {
        var types = parseBundleIdentifiers(ignoredPasteboardTypesText)
        if ignoreUniversalClipboard {
            types.insert("com.apple.is-remote-clipboard")
        }
        return types
    }

    var globalShortcut: GlobalShortcut {
        GlobalShortcut.presets.first { $0.id == globalShortcutPresetID }
            ?? GlobalShortcut.defaultShortcut
    }

    func setApplicationLockEnabled(_ enabled: Bool) {
        applicationLockEnabled = enabled
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
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        defaults.set(historyLimit, forKey: Key.historyLimit)
        defaults.set(thumbnailCacheMegabytes, forKey: Key.thumbnailCacheMegabytes)
        defaults.set(selectedFilter.rawValue, forKey: Key.selectedFilter)
        defaults.set(selectedSortMode.rawValue, forKey: Key.selectedSortMode)
        defaults.set(sensitiveStoragePolicy.rawValue, forKey: Key.sensitiveStoragePolicy)
        defaults.set(sensitiveRetentionSeconds, forKey: Key.sensitiveRetentionSeconds)
        defaults.set(excludedBundleIdentifiersText, forKey: Key.excludedBundleIdentifiersText)
        defaults.set(allowedBundleIdentifiersText, forKey: Key.allowedBundleIdentifiersText)
        defaults.set(autoLockOption.rawValue, forKey: Key.autoLockOption)
        defaults.set(applicationLockEnabled, forKey: Key.applicationLockEnabled)
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
        defaults.set(imageTextRecognitionEnabled, forKey: Key.imageTextRecognitionEnabled)
        defaults.set(ignoreUniversalClipboard, forKey: Key.ignoreUniversalClipboard)
        defaults.set(ignoredPasteboardTypesText, forKey: Key.ignoredPasteboardTypesText)
        defaults.set(pasteStackOrder.rawValue, forKey: Key.pasteStackOrder)
        defaults.set(pasteStackRemovesUsedItems, forKey: Key.pasteStackRemovesUsedItems)
        defaults.set(pasteStackTimeoutMinutes, forKey: Key.pasteStackTimeoutMinutes)
        defaults.set(globalShortcutPresetID, forKey: Key.globalShortcutPresetID)
        defaults.set(shortcutActivationMode.rawValue, forKey: Key.shortcutActivationMode)
        defaults.set(panelPresentationMode.rawValue, forKey: Key.panelPresentationMode)
        defaults.set(panelScreenEdge.rawValue, forKey: Key.panelScreenEdge)
        defaults.set(scrollReversalEnabled, forKey: Key.scrollReversalEnabled)
        defaults.set(reverseDiscreteScrollVertical, forKey: Key.reverseDiscreteScrollVertical)
        defaults.set(reverseDiscreteScrollHorizontal, forKey: Key.reverseDiscreteScrollHorizontal)
        defaults.set(reversePreciseScrollVertical, forKey: Key.reversePreciseScrollVertical)
        defaults.set(reversePreciseScrollHorizontal, forKey: Key.reversePreciseScrollHorizontal)
    }

    private static let suggestedExcludedApplications = """
    com.1password.1password
    com.agilebits.onepassword7
    com.bitwarden.desktop
    com.dashlane.Dashlane
    com.lastpass.LastPass
    com.apple.keychainaccess
    """
    private static let closePanelAfterCopyingMigrationVersion = 1
    private static let applicationLockMigrationVersion = 2

    private enum Key {
        static let globalShortcutEnabled = "globalShortcutEnabled"
        static let closePanelAfterCopying = "closePanelAfterCopying"
        static let closePanelAfterCopyingMigrationVersion = "closePanelAfterCopyingMigrationVersion"
        static let appearance = "appearance"
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
        static let applicationLockEnabled = "applicationLockEnabled"
        static let captureWhileLocked = "captureWhileLocked"
        static let applicationLockMigrationVersion = "applicationLockMigrationVersion"
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
        static let imageTextRecognitionEnabled = "imageTextRecognitionEnabled"
        static let ignoreUniversalClipboard = "ignoreUniversalClipboard"
        static let ignoredPasteboardTypesText = "ignoredPasteboardTypesText"
        static let pasteStackOrder = "pasteStackOrder"
        static let pasteStackRemovesUsedItems = "pasteStackRemovesUsedItems"
        static let pasteStackTimeoutMinutes = "pasteStackTimeoutMinutes"
        static let globalShortcutPresetID = "globalShortcutPresetID"
        static let shortcutActivationMode = "shortcutActivationMode"
        static let panelPresentationMode = "panelPresentationMode"
        static let panelScreenEdge = "panelScreenEdge"
        static let scrollReversalEnabled = "scrollReversalEnabled"
        static let reverseDiscreteScrollVertical = "reverseDiscreteScrollVertical"
        static let reverseDiscreteScrollHorizontal = "reverseDiscreteScrollHorizontal"
        static let reversePreciseScrollVertical = "reversePreciseScrollVertical"
        static let reversePreciseScrollHorizontal = "reversePreciseScrollHorizontal"
    }
}

private extension Int {
    func nonzero(or fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
