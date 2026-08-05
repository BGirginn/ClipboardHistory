import SwiftUI

struct ClipboardApplicationLockControls: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    @ViewBuilder
    var body: some View {
        if viewModel.isApplicationLockEnabled {
            LabeledContent("Status") {
                if viewModel.isLocked {
                    Label("Locked", systemImage: "lock.fill")
                } else {
                    Label("Unlocked", systemImage: "lock.open")
                }
            }
            .foregroundStyle(
                viewModel.isLocked
                    ? AnyShapeStyle(Color.orange)
                    : AnyShapeStyle(.secondary)
            )
            Picker(
                "Automatic lock",
                selection: $viewModel.settings.autoLockOption
            ) {
                ForEach(AutoLockOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Toggle(
                "Continue recording while locked",
                isOn: $viewModel.settings.captureWhileLocked
            )
            .help("New items remain encrypted. Viewing, copying, and pasting stay blocked until you unlock.")
            .accessibilityHint("When enabled, new clipboard items are encrypted and saved while the application is locked.")

            LabeledContent("Control") {
                if viewModel.isLocked {
                    Button("Authenticate and Unlock", systemImage: "touchid", action: toggleLock)
                } else {
                    Button("Lock Now", systemImage: "lock.fill", action: toggleLock)
                }
            }
            .buttonStyle(.bordered)
            .accessibilityValue(viewModel.isLocked ? "Locked" : "Unlocked")
            .accessibilityIdentifier("settings.lock")
        }
    }

    func toggleLock() {
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
        }
    }
}
