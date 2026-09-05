import SwiftUI

struct KeyboardCleaningCardView: View {
    let controller: KeyboardCleaningController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    controller.isActive
                        ? String(localized: "Keyboard input is blocked")
                        : String(localized: "Clean your keyboard without accidental typing"),
                    systemImage: controller.isActive
                        ? "keyboard.badge.ellipsis.fill"
                        : "keyboard.badge.ellipsis"
                )
                .font(.headline)

                if controller.isActive {
                    Text(
                        "Keyboard input stays blocked until you stop cleaning. Mouse input stays available."
                    )
                    .foregroundStyle(.secondary)

                    Button(
                        "Stop Keyboard Cleaning",
                        systemImage: "lock.open",
                        action: controller.stop
                    )
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("keyboardCleaning.stop")
                } else {
                    Text(
                        "Start with the mouse, then click again when cleaning is complete. Sleep, sign-out, or quitting always releases the keyboard."
                    )
                    .foregroundStyle(.secondary)

                    KeyboardCleaningAvailabilityView(controller: controller)

                    if !controller.permissionRequired {
                        Button(
                            "Start Keyboard Cleaning",
                            systemImage: "lock.keyboard",
                            action: controller.start
                        )
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("keyboardCleaning.start")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Keyboard Cleaning Mode")
        }
        .accessibilityIdentifier("keyboardCleaning.card")
    }

}
