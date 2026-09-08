import SwiftUI

struct KeyboardCleaningControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: KeyboardCleaningController
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlCenterFeatureCard(
                title: descriptor.title,
                summary: controller.isActive
                    ? String(localized: "Keyboard Cleaning is active")
                    : String(localized: "Ready"),
                systemImage: controller.isActive
                    ? "keyboard.badge.ellipsis.fill"
                    : descriptor.systemImage,
                accessorySystemImage: "chevron.right",
                accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
                action: action
            )
            Button(controller.isActive ? "Stop Keyboard Cleaning" : "Start Keyboard Cleaning",
                   systemImage: controller.isActive ? "stop.circle.fill" : "play.circle",
                   action: controller.toggle)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title2)
                .frame(width: 36, height: 44)
                .accessibilityIdentifier("controlCenter.keyboardCleaning.toggle")
        }
    }
}
