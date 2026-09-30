import Foundation

struct FeatureRegistry: Sendable {
    let descriptors: [FeatureDescriptor]

    func descriptor(for id: UtilityFeatureID) -> FeatureDescriptor? {
        descriptors.first { $0.id == id }
    }

    func validatedAction(_ action: FeatureClickAction, for id: UtilityFeatureID) -> FeatureClickAction {
        guard let descriptor = descriptor(for: id) else { return .open }
        return descriptor.supportedClickActions.contains(action)
            ? action
            : descriptor.defaultClickAction
    }

    static let live = FeatureRegistry(
        descriptors: [
            FeatureDescriptor(
                id: .clipboard,
                title: String(localized: "Clipboard"),
                summary: String(localized: "Capture, find, and reuse clipboard items"),
                systemImage: "clipboard",
                supportedClickActions: [.open, .toggleClipboardRecording],
                defaultClickAction: .open,
                supportedMenuBarVisibilityPolicies: [.hidden, .whenActive, .always]
            ),
            FeatureDescriptor(
                id: .notes,
                title: String(localized: "Notes"),
                summary: String(localized: "Create and edit encrypted notes"),
                systemImage: "note.text",
                supportedClickActions: [.open, .newNote],
                defaultClickAction: .open
            ),
            FeatureDescriptor(
                id: .keyboardCleaning,
                title: String(localized: "Keyboard Cleaning"),
                summary: String(localized: "Temporarily block keyboard input"),
                systemImage: "keyboard.badge.ellipsis",
                supportedClickActions: [.open, .toggleKeyboardCleaning],
                defaultClickAction: .toggleKeyboardCleaning,
                supportedMenuBarVisibilityPolicies: [.hidden, .whenActive, .always]
            ),
            FeatureDescriptor(
                id: .scrollReverse,
                title: String(localized: "Scroll Reverse"),
                summary: String(localized: "Reverse mouse or trackpad scrolling"),
                systemImage: "arrow.up.arrow.down.circle",
                supportedClickActions: [.open, .toggleScrollReverse],
                defaultClickAction: .open,
                supportedMenuBarVisibilityPolicies: [.hidden, .whenActive, .always]
            ),
            FeatureDescriptor(
                id: .systemMonitor,
                title: String(localized: "System Monitor"),
                summary: String(localized: "Live CPU, memory, temperature, network, and disk usage"),
                systemImage: "gauge.with.dots.needle.67percent",
                supportedClickActions: [.open],
                defaultClickAction: .open
            ),
            FeatureDescriptor(
                id: .audioMixer,
                title: String(localized: "Audio Mixer"),
                summary: String(localized: "Control application and supported browser-tab volume"),
                systemImage: "slider.horizontal.3",
                supportedClickActions: [.open, .muteAllAudio],
                defaultClickAction: .open,
                supportedMenuBarVisibilityPolicies: [.hidden, .whenActive, .always]
            )
        ]
    )
}
