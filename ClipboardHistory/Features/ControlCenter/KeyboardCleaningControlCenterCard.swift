import SwiftUI

struct KeyboardCleaningControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: KeyboardCleaningController
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: controller.isActive
                ? String(localized: "Keyboard Cleaning is active")
                : String(localized: "Click to start cleaning"),
            systemImage: controller.isActive
                ? "keyboard.badge.ellipsis.fill"
                : descriptor.systemImage,
            accessorySystemImage: controller.isActive ? "stop.circle.fill" : "play.circle",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }
}
