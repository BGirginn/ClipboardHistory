import SwiftUI

struct ClipboardSettingsSecurityView: View {
    @ObservedObject var viewModel: SettingsFeatureModel

    var body: some View {
        Form {
            Section("Application Lock") {
                ClipboardApplicationLockControls(viewModel: viewModel)

                Button(
                    viewModel.isApplicationLockEnabled
                        ? "Authenticate and Disable Application Lock"
                        : "Authenticate and Enable Application Lock",
                    systemImage: viewModel.isApplicationLockEnabled ? "lock.slash" : "touchid",
                    action: changeApplicationLockSetting
                )
                .disabled(viewModel.lockService.isAuthenticating)
                .accessibilityHint("Uses Touch ID or your Mac login password. Clipboard History does not create a separate password.")

                ClipboardSettingsMessage(
                    message: viewModel.lockService.errorMessage,
                    color: .red
                )
                .accessibilityLabel(
                    viewModel.lockService.errorMessage.map(applicationLockAccessibilityLabel) ?? ""
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.security")
    }

    func toggleLock() {
        if viewModel.isLocked {
            viewModel.unlock()
        } else {
            viewModel.lock()
        }
    }

    func changeApplicationLockSetting() {
        viewModel.setApplicationLockEnabled(!viewModel.isApplicationLockEnabled)
    }

    func applicationLockAccessibilityLabel(_ message: String) -> String {
        String(localized: "Application lock error: \(message)")
    }
}
