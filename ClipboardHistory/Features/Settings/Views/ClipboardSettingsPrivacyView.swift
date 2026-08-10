import SwiftUI

struct ClipboardSettingsPrivacyView: View {
    @ObservedObject var viewModel: SettingsFeatureModel

    var body: some View {
        Form {
            Section("Sensitive Content") {
                Toggle(
                    "Detect secrets locally",
                    isOn: $viewModel.settings.secretDetectionEnabled
                )

                Picker(
                    "Sensitive content",
                    selection: $viewModel.settings.sensitiveStoragePolicy
                ) {
                    ForEach(SensitiveStoragePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                LabeledContent("Temporary retention") {
                    Stepper(
                        value: $viewModel.settings.sensitiveRetentionSeconds,
                        in: 10...600,
                        step: 10
                    ) {
                        Text("\(viewModel.settings.sensitiveRetentionSeconds) seconds")
                        .monospacedDigit()
                    }
                }
            }

            Section("Recording") {
                LabeledContent("Status") {
                    ClipboardRecordingStatusView(
                        isPrivateMode: viewModel.isPrivateMode,
                        pauseUntil: viewModel.pauseUntil
                    )
                }

                Toggle("Private Mode", isOn: privateModeBinding)
                    .accessibilityIdentifier("settings.privateMode")

                Toggle(
                    "Start in Private Mode",
                    isOn: $viewModel.settings.privateModeDefaultEnabled
                )

                LabeledContent("Temporary mode") {
                    Menu("Choose Duration", systemImage: "timer") {
                        Button("5 Minutes") { viewModel.enablePrivateMode(minutes: 5) }
                        Button("15 Minutes") { viewModel.enablePrivateMode(minutes: 15) }
                        Button("60 Minutes") { viewModel.enablePrivateMode(minutes: 60) }
                    }
                    .accessibilityIdentifier("settings.privateModeDuration")
                }

                LabeledContent("Pause recording") {
                    Menu("Choose Duration", systemImage: "pause.circle") {
                        Button("5 Minutes") { viewModel.pauseRecording(minutes: 5) }
                        Button("15 Minutes") { viewModel.pauseRecording(minutes: 15) }
                        Button("60 Minutes") { viewModel.pauseRecording(minutes: 60) }
                    }
                    .accessibilityIdentifier("settings.pauseDuration")
                }

                if viewModel.isPaused {
                    Button(
                        "Resume Recording",
                        systemImage: "play.fill",
                        action: viewModel.resumeRecording
                    )
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("settings.resumeRecording")
                }
            }

            Section("Application Rules") {
                TextField(
                    "Excluded bundle identifiers",
                    text: $viewModel.settings.excludedBundleIdentifiersText,
                    axis: .vertical
                )
                .font(.body.monospaced())
                .lineLimit(3...6)
                .accessibilityIdentifier("settings.excludedApps")

                TextField(
                    "Always allowed bundle identifiers",
                    text: $viewModel.settings.allowedBundleIdentifiersText,
                    axis: .vertical
                )
                .font(.body.monospaced())
                .lineLimit(2...4)
                .accessibilityIdentifier("settings.allowedApps")

                Text("Allowed applications override exclusions. Excluded clipboard content is never read or stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ExcludedApplicationListView(
                    bundleIdentifiers: Array(
                        viewModel.settings.excludedBundleIdentifiers
                    ).sorted()
                )
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.privacy")
    }

}

extension ClipboardSettingsPrivacyView {
    var privateModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isPrivateMode },
            set: { enabled in
                viewModel.setPrivateModeEnabled(enabled)
            }
        )
    }
}
