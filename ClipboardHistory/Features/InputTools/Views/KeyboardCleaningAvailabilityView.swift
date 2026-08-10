import SwiftUI

struct KeyboardCleaningAvailabilityView: View {
    @ObservedObject var controller: KeyboardCleaningController

    var body: some View {
        Group {
            if controller.permissionRequired {
                Label(
                    "Accessibility permission is required to block keyboard input.",
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
                    .accessibilityIdentifier("keyboardCleaning.error")
            }
        }
    }
}
