import SwiftUI

struct AudioMixerSettingsView: View {
    @ObservedObject var controller: AudioMixerController
    let selectedSubsection: AppSettingsSubsection

    init(
        controller: AudioMixerController,
        selectedSubsection: AppSettingsSubsection = .audioSystem
    ) {
        self.controller = controller
        self.selectedSubsection = selectedSubsection
    }

    var body: some View {
        Form {
            if selectedSubsection == .audioSystem {
                Section("System Audio") {
                    LabeledContent("Permission") {
                        Text(permissionText)
                    }
                    Text("Audio is processed in memory only. ClipboardHistory never records, stores, analyzes, or logs audio samples.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if selectedSubsection == .audioChromium {
                Section("Chromium Companion Extension") {
                    Button(
                        "Prepare Extension and Native Host",
                        systemImage: "puzzlepiece.extension",
                        action: controller.installChromiumExtension
                    )
                    Text("After preparing the files, open Brave, Chrome, Edge, or Arc Extensions, enable Developer Mode, choose Load unpacked, and select the revealed folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if selectedSubsection == .audioSafari {
                Section("Safari Companion Extension") {
                    Button(
                        "Open Safari Extension Settings",
                        systemImage: "safari",
                        action: controller.openSafariExtensionSettings
                    )
                    Text("Enable ClipboardHistory Safari Audio and grant website access. Only tabs with directly controllable HTML audio or video are listed; DRM, Web Audio and protected pages are excluded.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if selectedSubsection == .audioReset {
                Section("Reset") {
                    Button(
                        "Reset All Volumes to 100%",
                        systemImage: "arrow.counterclockwise",
                        action: controller.resetAll
                    )
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "Browser Extension",
            isPresented: Binding(
                get: { controller.extensionMessage != nil },
                set: { if !$0 { controller.extensionMessage = nil } }
            )
        ) { } message: {
            Text(controller.extensionMessage ?? "")
        }
    }

    private var permissionText: String {
        switch controller.permissionState {
        case .notRequested: String(localized: "Not Requested")
        case .requesting: String(localized: "Requesting")
        case .ready: String(localized: "Ready")
        case .denied: String(localized: "Denied")
        case .failed: String(localized: "Needs Attention")
        }
    }
}
