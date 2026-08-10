import SwiftUI

struct AudioMixerView: View {
    @ObservedObject var controller: AudioMixerController
    let close: () -> Void
    let openSettings: () -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            ModuleToolbar(
                title: String(localized: "Audio Mixer"),
                subtitle: String(localized: "Applications and authorized browser tabs"),
                backTitle: String(localized: "Back to Control Center"),
                back: close,
                openSettings: openSettings
            ) {
                Menu("Audio Actions", systemImage: "ellipsis.circle") {
                    Button(
                        controller.isEverythingMuted ? "Restore Audio" : "Mute All",
                        systemImage: controller.isEverythingMuted ? "speaker.wave.2" : "speaker.slash",
                        action: controller.toggleMuteAll
                    )
                    Button("Reset All to 100%", systemImage: "arrow.counterclockwise", action: controller.resetAll)
                }
                .menuStyle(.borderlessButton)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    if let message = controller.permissionState.message {
                        Label(message, systemImage: "waveform.badge.exclamationmark")
                            .font(.subheadline)
                            .padding(AppDesign.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
                    }
                    AudioMixerApplicationSection(
                        applications: filteredApplications,
                        controller: controller
                    )
                    AudioMixerBrowserSection(controller: controller)
                }
                .padding(AppDesign.horizontalPadding)
            }
            .searchable(text: $searchText, prompt: "Search Applications")
        }
        .task {
            controller.startRefreshing()
            defer { controller.stopRefreshing() }
            try? await Task.sleep(for: .seconds(31_536_000))
        }
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

    private var filteredApplications: [AudioApplication] {
        guard !searchText.isEmpty else { return controller.applications }
        return controller.applications.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.bundleID.localizedStandardContains(searchText)
        }
    }
}
