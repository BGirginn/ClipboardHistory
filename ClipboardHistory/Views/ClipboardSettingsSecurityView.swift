import SwiftUI

struct ClipboardSettingsSecurityView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        Form {
            Section("Encryption") {
                Picker("Encryption", selection: $viewModel.settings.encryptionMode) {
                    ForEach(EncryptionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text("Keys are stored in the macOS Data Protection Keychain. Item type, dates, sizes, hashes, and source application remain visible as metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Application Lock") {
                LabeledContent("Status") {
                    Label(
                        viewModel.isLocked ? "Locked" : "Unlocked",
                        systemImage: viewModel.isLocked ? "lock.fill" : "lock.open"
                    )
                    .foregroundStyle(
                        viewModel.isLocked
                            ? AnyShapeStyle(Color.orange)
                            : AnyShapeStyle(.secondary)
                    )
                }

                Picker(
                    "Automatic lock",
                    selection: $viewModel.settings.autoLockOption
                ) {
                    ForEach(AutoLockOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                LabeledContent("Control") {
                    Button(
                        viewModel.isLocked ? "Authenticate and Unlock" : "Lock Now",
                        systemImage: viewModel.isLocked ? "touchid" : "lock.fill",
                        action: toggleLock
                    )
                    .buttonStyle(.bordered)
                    .accessibilityValue(viewModel.isLocked ? "Locked" : "Unlocked")
                    .accessibilityIdentifier("settings.lock")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.security")
    }

    private func toggleLock() {
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
        }
    }
}
