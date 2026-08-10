import SwiftUI

struct AudioMixerSettingsView: View {
    @ObservedObject var viewModel: SettingsFeatureModel

    var body: some View {
        Form {
            Section("System Audio") {
                LabeledContent("Permission") {
                    Text(permissionText)
                }
                Text("Audio is processed in memory only. ClipboardHistory never records, stores, analyzes, or logs audio samples.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Chromium Companion Extension") {
                Button(
                    "Prepare Extension and Native Host",
                    systemImage: "puzzlepiece.extension",
                    action: viewModel.audioMixer.installChromiumExtension
                )
                Text("After preparing the files, open Brave, Chrome, Edge, or Arc Extensions, enable Developer Mode, choose Load unpacked, and select the revealed folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Safari Companion Extension") {
                Button(
                    "Open Safari Extension Settings",
                    systemImage: "safari",
                    action: viewModel.audioMixer.openSafariExtensionSettings
                )
                Text("Enable ClipboardHistory Safari Audio and grant website access. Only tabs with directly controllable HTML audio or video are listed; DRM, Web Audio and protected pages are excluded.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Reset") {
                Button("Reset All Volumes to 100%", systemImage: "arrow.counterclockwise", action: viewModel.audioMixer.resetAll)
            }
        }
        .formStyle(.grouped)
    }

    private var permissionText: String {
        switch viewModel.audioMixer.permissionState {
        case .notRequested: String(localized: "Not Requested")
        case .ready: String(localized: "Ready")
        case .denied: String(localized: "Denied")
        case .failed: String(localized: "Needs Attention")
        }
    }
}
