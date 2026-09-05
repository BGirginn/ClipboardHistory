import SwiftUI

struct ClipboardControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: ClipboardHistoryViewModel
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: summary,
            systemImage: controller.isPaused ? "pause.circle" : descriptor.systemImage,
            accessorySystemImage: "chevron.right",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }

    private var summary: String {
        if controller.isPrivateMode { return String(localized: "Private Mode is active") }
        if controller.isPaused { return String(localized: "Recording is paused") }
        return controller.items.count == 1
            ? String(localized: "1 saved item")
            : String(localized: "\(controller.items.count) saved items")
    }
}
