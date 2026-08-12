import SwiftUI

struct ClipboardApplicationLockControls: View {
    @ObservedObject var viewModel: SettingsFeatureModel

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

            Text("Clipboard recording pauses while the application is locked.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
