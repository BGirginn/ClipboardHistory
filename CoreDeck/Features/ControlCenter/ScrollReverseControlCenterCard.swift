import SwiftUI

struct ScrollReverseControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: ScrollReversalController
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: controller.isActive
                ? String(localized: "Scroll Reverse is active")
                : String(localized: "Native scrolling is unchanged"),
            systemImage: controller.isActive
                ? "arrow.up.arrow.down.circle.fill"
                : descriptor.systemImage,
            accessorySystemImage: "chevron.right",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }
}
