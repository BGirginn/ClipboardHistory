import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var globalShortcutEnabled: Bool {
        didSet { persist(globalShortcutEnabled, oldValue, Key.globalShortcutEnabled) }
    }
    @Published var closePanelAfterCopying: Bool {
        didSet { persist(closePanelAfterCopying, oldValue, Key.closePanelAfterCopying) }
    }
    @Published var appearance: AppAppearance {
        didSet { persist(appearance.rawValue, oldValue.rawValue, Key.appearance) }
    }
    @Published var historyLimit: Int {
        didSet { persist(historyLimit, oldValue, Key.historyLimit) }
    }
    @Published var thumbnailCacheMegabytes: Int {
        didSet { persist(thumbnailCacheMegabytes, oldValue, Key.thumbnailCacheMegabytes) }
    }
    @Published var selectedFilter: ClipboardFilter {
        didSet { persist(selectedFilter.rawValue, oldValue.rawValue, Key.selectedFilter) }
    }
    @Published var selectedSortMode: ClipboardSortMode {
        didSet { persist(selectedSortMode.rawValue, oldValue.rawValue, Key.selectedSortMode) }
    }
    @Published var sensitiveStoragePolicy: SensitiveStoragePolicy {
        didSet { persist(sensitiveStoragePolicy.rawValue, oldValue.rawValue, Key.sensitiveStoragePolicy) }
    }
    @Published var sensitiveRetentionSeconds: Int {
        didSet { persist(sensitiveRetentionSeconds, oldValue, Key.sensitiveRetentionSeconds) }
    }
    @Published var excludedBundleIdentifiersText: String {
        didSet { persist(excludedBundleIdentifiersText, oldValue, Key.excludedBundleIdentifiersText) }
    }
    @Published var allowedBundleIdentifiersText: String {
        didSet { persist(allowedBundleIdentifiersText, oldValue, Key.allowedBundleIdentifiersText) }
    }
    @Published var retentionDays: Int {
        didSet { persist(retentionDays, oldValue, Key.retentionDays) }
    }
    @Published var imageRetentionDays: Int {
        didSet { persist(imageRetentionDays, oldValue, Key.imageRetentionDays) }
    }
    @Published var maximumStorageMegabytes: Int {
        didSet { persist(maximumStorageMegabytes, oldValue, Key.maximumStorageMegabytes) }
    }
    @Published var duplicateDetectionScope: DuplicateDetectionScope {
        didSet { persist(duplicateDetectionScope.rawValue, oldValue.rawValue, Key.duplicateDetectionScope) }
    }
    @Published var secretDetectionEnabled: Bool {
        didSet { persist(secretDetectionEnabled, oldValue, Key.secretDetectionEnabled) }
    }
    @Published var privateModeDefaultEnabled: Bool {
        didSet { persist(privateModeDefaultEnabled, oldValue, Key.privateModeDefaultEnabled) }
    }
    @Published var launchAtLoginRequested: Bool {
        didSet { persist(launchAtLoginRequested, oldValue, Key.launchAtLoginRequested) }
    }
    @Published var captureRichText: Bool {
        didSet { persist(captureRichText, oldValue, Key.captureRichText) }
    }
    @Published var capturePDFs: Bool {
        didSet { persist(capturePDFs, oldValue, Key.capturePDFs) }
    }
    @Published var captureFiles: Bool {
        didSet { persist(captureFiles, oldValue, Key.captureFiles) }
    }
    @Published var imageTextRecognitionEnabled: Bool {
        didSet { persist(imageTextRecognitionEnabled, oldValue, Key.imageTextRecognitionEnabled) }
    }
    @Published var ignoreUniversalClipboard: Bool {
        didSet { persist(ignoreUniversalClipboard, oldValue, Key.ignoreUniversalClipboard) }
    }
    @Published var ignoredPasteboardTypesText: String {
        didSet { persist(ignoredPasteboardTypesText, oldValue, Key.ignoredPasteboardTypesText) }
    }
    @Published var pasteStackOrder: PasteStackOrder {
        didSet { persist(pasteStackOrder.rawValue, oldValue.rawValue, Key.pasteStackOrder) }
    }
    @Published var pasteStackRemovesUsedItems: Bool {
        didSet { persist(pasteStackRemovesUsedItems, oldValue, Key.pasteStackRemovesUsedItems) }
    }
    @Published var pasteStackTimeoutMinutes: Int {
        didSet { persist(pasteStackTimeoutMinutes, oldValue, Key.pasteStackTimeoutMinutes) }
    }
    @Published var globalShortcutPresetID: String {
        didSet { persist(globalShortcutPresetID, oldValue, Key.globalShortcutPresetID) }
    }
    @Published var shortcutActivationMode: ShortcutActivationMode {
        didSet { persist(shortcutActivationMode.rawValue, oldValue.rawValue, Key.shortcutActivationMode) }
    }
    @Published var panelPresentationMode: PanelPresentationMode {
        didSet { persist(panelPresentationMode.rawValue, oldValue.rawValue, Key.panelPresentationMode) }
    }
    @Published var panelScreenEdge: PanelScreenEdge {
        didSet { persist(panelScreenEdge.rawValue, oldValue.rawValue, Key.panelScreenEdge) }
    }
    @Published var scrollReversalEnabled: Bool {
        didSet { persist(scrollReversalEnabled, oldValue, Key.scrollReversalEnabled) }
    }
    @Published var reverseDiscreteScrollVertical: Bool {
        didSet { persist(reverseDiscreteScrollVertical, oldValue, Key.reverseDiscreteScrollVertical) }
    }
    @Published var reverseDiscreteScrollHorizontal: Bool {
        didSet { persist(reverseDiscreteScrollHorizontal, oldValue, Key.reverseDiscreteScrollHorizontal) }
    }
    @Published var reversePreciseScrollVertical: Bool {
        didSet { persist(reversePreciseScrollVertical, oldValue, Key.reversePreciseScrollVertical) }
    }
    @Published var reversePreciseScrollHorizontal: Bool {
        didSet { persist(reversePreciseScrollHorizontal, oldValue, Key.reversePreciseScrollHorizontal) }
    }

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
        defaults.removeObject(forKey: Key.autoLockOption)
        defaults.removeObject(forKey: Key.applicationLockEnabled)
        defaults.removeObject(forKey: Key.captureWhileLocked)
        defaults.removeObject(forKey: Key.applicationLockMigrationVersion)
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

    private func parseBundleIdentifiers(_ value: String) -> Set<String> {
        Set(
            value.split { character in
                character.isWhitespace || character == "," || character == ";"
            }.map { $0.lowercased() }
        )
    }

    private func persist<Value: Equatable>(_ value: Value, _ oldValue: Value, _ key: String) {
        guard value != oldValue else { return }
        defaults.set(value, forKey: key)
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
