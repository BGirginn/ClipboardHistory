import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var controlCenter: ControlCenterModel
    let clipboard: ClipboardHistoryViewModel
    let notes: NoteController
    let keyboardCleaning: KeyboardCleaningController
    let scrollReversal: ScrollReversalController
    let systemMetrics: SystemMetricsController
    let audioMixer: AudioMixerController
    let showFeature: (UtilityFeatureID) -> Void
    let customizeMenuBar: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controlCenterToolbar
            Divider()

            ScrollView {
                LazyVStack(spacing: AppDesign.sectionSpacing) {
                    if controlCenter.controlCenterFeatures.isEmpty {
                        ContentUnavailableView(
                            "No Modules in Control Center",
                            systemImage: "square.grid.2x2",
                            description: Text("Use Customize Menu Bar to add modules here.")
                        )
                    } else {
                        if controlCenter.controlCenterFeatures.contains(where: { $0.id == .clipboard }) {
                            QuickCenterClipboardSection(
                                controller: clipboard,
                                openClipboard: { showFeature(.clipboard) }
                            )
                        }
                        if controlCenter.controlCenterFeatures.contains(where: { $0.id == .notes }) {
                            QuickCenterNoteSection(
                                controller: notes,
                                openNotes: { showFeature(.notes) }
                            )
                        }
                        ForEach(moduleFeatures) { descriptor in
                            featureCard(for: descriptor)
                        }
                    }
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
        .task(id: controlCenter.controlCenterFeatures.contains { $0.id == .notes }) {
            if controlCenter.controlCenterFeatures.contains(where: { $0.id == .notes }) {
                await notes.loadIfNeeded()
            }
        }
    }

    private var moduleFeatures: [FeatureDescriptor] {
        controlCenter.controlCenterFeatures.filter { ![.clipboard, .notes].contains($0.id) }
    }

    private var controlCenterToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CoreDeck")
                    .font(.title3)
                    .bold()
                Text("Your local Mac control center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            OpenInWindowButton()
            Button("Customize Menu Bar", systemImage: "switch.2", action: customizeMenuBar)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
                .help("Customize Menu Bar")
                .accessibilityIdentifier("controlCenter.customize")
            Button("Open Settings", systemImage: "gearshape", action: openSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
                .help("Open Settings")
                .accessibilityIdentifier("controlCenter.settings")
        }
        .padding(.horizontal, AppDesign.horizontalPadding)
        .padding(.vertical, AppDesign.toolbarVerticalPadding)
    }

    @ViewBuilder
    private func featureCard(for descriptor: FeatureDescriptor) -> some View {
        switch descriptor.id {
        case .clipboard:
            ClipboardControlCenterCard(
                descriptor: descriptor,
                controller: clipboard,
                action: { showFeature(.clipboard) }
            )
        case .notes:
            NotesControlCenterCard(
                descriptor: descriptor,
                controller: notes,
                action: { showFeature(.notes) }
            )
        case .keyboardCleaning:
            KeyboardCleaningControlCenterCard(
                descriptor: descriptor,
                controller: keyboardCleaning,
                action: { showFeature(.keyboardCleaning) }
            )
        case .scrollReverse:
            ScrollReverseControlCenterCard(
                descriptor: descriptor,
                controller: scrollReversal,
                action: { showFeature(.scrollReverse) }
            )
        case .systemMonitor:
            SystemMonitorControlCenterCard(
                descriptor: descriptor,
                controller: systemMetrics,
                action: { showFeature(.systemMonitor) }
            )
        case .audioMixer:
            AudioMixerControlCenterCard(
                descriptor: descriptor,
                controller: audioMixer,
                action: { showFeature(.audioMixer) }
            )
        }
    }
}
