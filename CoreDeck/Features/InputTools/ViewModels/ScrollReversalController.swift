import Combine
import Foundation

@MainActor
final class ScrollReversalController: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { settingDidChange(requestPermission: isEnabled) }
    }
    @Published var reversesDiscreteVertical: Bool {
        didSet { settingDidChange(requestPermission: isEnabled) }
    }
    @Published var reversesDiscreteHorizontal: Bool {
        didSet { settingDidChange(requestPermission: isEnabled) }
    }
    @Published var reversesPreciseVertical: Bool {
        didSet { settingDidChange(requestPermission: isEnabled) }
    }
    @Published var reversesPreciseHorizontal: Bool {
        didSet { settingDidChange(requestPermission: isEnabled) }
    }
    @Published private(set) var isActive = false
    @Published private(set) var permissionRequired = false
    @Published private(set) var errorMessage: String?

    private let coordinator: any InputEventTapCoordinating
    private let settings: AppSettings

    init(
        coordinator: any InputEventTapCoordinating,
        settings: AppSettings
    ) {
        self.coordinator = coordinator
        self.settings = settings
        isEnabled = settings.scrollReversalEnabled
        reversesDiscreteVertical = settings.reverseDiscreteScrollVertical
        reversesDiscreteHorizontal = settings.reverseDiscreteScrollHorizontal
        reversesPreciseVertical = settings.reversePreciseScrollVertical
        reversesPreciseHorizontal = settings.reversePreciseScrollHorizontal
    }

    var configuration: ScrollReversalConfiguration {
        ScrollReversalConfiguration(
            isEnabled: isEnabled,
            reversesDiscreteVertical: reversesDiscreteVertical,
            reversesDiscreteHorizontal: reversesDiscreteHorizontal,
            reversesPreciseVertical: reversesPreciseVertical,
            reversesPreciseHorizontal: reversesPreciseHorizontal
        )
    }

    func activatePersistedPreference() {
        applyConfiguration(requestPermission: false)
    }

    func retryAfterPermissionChange() {
        applyConfiguration(requestPermission: false)
    }

    func openAccessibilitySettings() {
        coordinator.openAccessibilitySettings()
    }

    func disable() {
        isEnabled = false
    }

    func refreshAfterWake() {
        applyConfiguration(requestPermission: false)
    }

    func suspend() {
        _ = coordinator.setScrollReversal(.disabled)
        isActive = false
    }

    func eventTapDidFail() {
        guard configuration.hasActiveAxis else { return }
        isActive = false
        errorMessage = String(
            localized: "Scroll Reverse stopped unexpectedly. Check Accessibility permission and try again."
        )
    }

    private func settingDidChange(requestPermission: Bool = false) {
        persistSettings()
        applyConfiguration(requestPermission: requestPermission)
    }

    private func persistSettings() {
        if settings.scrollReversalEnabled != isEnabled {
            settings.scrollReversalEnabled = isEnabled
        }
        if settings.reverseDiscreteScrollVertical != reversesDiscreteVertical {
            settings.reverseDiscreteScrollVertical = reversesDiscreteVertical
        }
        if settings.reverseDiscreteScrollHorizontal != reversesDiscreteHorizontal {
            settings.reverseDiscreteScrollHorizontal = reversesDiscreteHorizontal
        }
        if settings.reversePreciseScrollVertical != reversesPreciseVertical {
            settings.reversePreciseScrollVertical = reversesPreciseVertical
        }
        if settings.reversePreciseScrollHorizontal != reversesPreciseHorizontal {
            settings.reversePreciseScrollHorizontal = reversesPreciseHorizontal
        }
    }

    private func applyConfiguration(requestPermission: Bool) {
        let configuration = configuration
        guard configuration.hasActiveAxis else {
            _ = coordinator.setScrollReversal(.disabled)
            isActive = false
            permissionRequired = false
            errorMessage = nil
            return
        }

        if !coordinator.isTrusted, requestPermission {
            _ = coordinator.requestAccessibilityAccess()
        }
        guard coordinator.isTrusted else {
            _ = coordinator.setScrollReversal(.disabled)
            isActive = false
            permissionRequired = true
            errorMessage = nil
            return
        }
        permissionRequired = false
        guard coordinator.setScrollReversal(configuration) else {
            isActive = false
            errorMessage = String(
                localized: "Scroll Reverse could not start. Check Accessibility permission and try again."
            )
            return
        }
        isActive = true
        errorMessage = nil
    }
}
