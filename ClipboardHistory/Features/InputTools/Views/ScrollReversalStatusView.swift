import SwiftUI

struct ScrollReversalStatusView: View {
    @ObservedObject var controller: ScrollReversalController

    var body: some View {
        Group {
            if controller.permissionRequired {
                Label(
                    "Accessibility permission is required to reverse scrolling.",
                    systemImage: "exclamationmark.shield"
                )
                .foregroundStyle(.orange)

                HStack {
                    Button(
                        "Open Accessibility Settings",
                        systemImage: "gearshape",
                        action: controller.openAccessibilitySettings
                    )
                    Button("Try Again", action: controller.retryAfterPermissionChange)
                        .buttonStyle(.borderedProminent)
                }
            } else if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("scrollReversal.error")
            } else if controller.isActive {
                Label("Scroll Reverse is active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("scrollReversal.active")
            } else {
                Label("Select at least one axis to reverse.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
