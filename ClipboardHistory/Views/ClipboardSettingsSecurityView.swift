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

                #if COMMUNITY
                Text("Keys are stored in the macOS login Keychain and access is bound to the stable Community Beta signing identity. Item type, dates, sizes, hashes, and source application remain visible as metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("Keys are stored in the macOS Data Protection Keychain. Item type, dates, sizes, hashes, and source application remain visible as metadata.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }

            Section("Application Lock") {
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

                Button(
                    viewModel.isApplicationLockEnabled
                        ? "Authenticate and Disable Application Lock"
                        : "Authenticate and Enable Application Lock",
                    systemImage: viewModel.isApplicationLockEnabled ? "lock.slash" : "touchid",
                    action: changeApplicationLockSetting
                )
                .disabled(viewModel.lockService.isAuthenticating)
                .accessibilityHint("Uses Touch ID or your Mac login password. Clipboard History does not create a separate password.")

                if let message = viewModel.lockService.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Application lock error: \(message)")
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

    private func changeApplicationLockSetting() {
        viewModel.setApplicationLockEnabled(!viewModel.isApplicationLockEnabled)
    }
}
