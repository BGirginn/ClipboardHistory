import SwiftUI

struct KeyboardCleaningCardView: View {
    @ObservedObject var controller: KeyboardCleaningController
    let isLocked: Bool

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
                        "Keyboard input unlocks automatically in \(controller.remainingSeconds) seconds. Mouse input stays available."
                    )
                    .foregroundStyle(.secondary)

                    ProgressView(
                        value: Double(controller.remainingSeconds),
                        total: KeyboardCleaningController.defaultDuration
                    )
                    .accessibilityLabel("Keyboard Cleaning Mode remaining time")
                    .accessibilityValue("\(controller.remainingSeconds) seconds")

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
                        "Keyboard input is blocked for 60 seconds. You can stop early with the mouse from this screen or the menu-bar right-click menu."
                    )
                    .foregroundStyle(.secondary)

                    KeyboardCleaningAvailabilityView(controller: controller)

                    if isLocked {
                        Label(
                            "Unlock the app to start Keyboard Cleaning.",
                            systemImage: "lock.fill"
                        )
                        .foregroundStyle(.secondary)
                    } else if !controller.permissionRequired {
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
