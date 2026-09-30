import SwiftUI

struct ClipboardSettingsPrivacyView: View {
    @ObservedObject var viewModel: SettingsFeatureModel
    @ObservedObject private var settings: AppSettings

    init(viewModel: SettingsFeatureModel) {
        self.viewModel = viewModel
        _settings = ObservedObject(wrappedValue: viewModel.settings)
    }

    var body: some View {
        Form {
            Section("Sensitive Content") {
                Toggle(
                    "Detect secrets locally",
                    isOn: $settings.secretDetectionEnabled
                )

                Picker(
                    "Sensitive content",
                    selection: $settings.sensitiveStoragePolicy
                ) {
                    ForEach(SensitiveStoragePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                LabeledContent("Temporary retention") {
                    Stepper(
                        value: $settings.sensitiveRetentionSeconds,
                        in: 10...600,
                        step: 10
                    ) {
                        Text("\(settings.sensitiveRetentionSeconds) seconds")
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
                    isOn: $settings.privateModeDefaultEnabled
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
                    text: $settings.excludedBundleIdentifiersText,
                    axis: .vertical
                )
                .font(.body.monospaced())
                .lineLimit(3...6)
                .accessibilityIdentifier("settings.excludedApps")

                TextField(
                    "Always allowed bundle identifiers",
                    text: $settings.allowedBundleIdentifiersText,
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
                        settings.excludedBundleIdentifiers
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
