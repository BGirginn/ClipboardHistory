import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var controlCenter: ControlCenterModel
    @ObservedObject var clipboard: ClipboardHistoryViewModel
    @ObservedObject var notes: NoteController
    @ObservedObject var keyboardCleaning: KeyboardCleaningController
    @ObservedObject var scrollReversal: ScrollReversalController
    @ObservedObject var systemMetrics: SystemMetricsController
    @ObservedObject var audioMixer: AudioMixerController
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
                        ForEach(controlCenter.controlCenterFeatures) { descriptor in
                            ControlCenterFeatureCard(
                                title: descriptor.title,
                                summary: summary(for: descriptor.id),
                                systemImage: symbol(for: descriptor),
                                accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
                                action: { showFeature(descriptor.id) }
                            )
                        }
                    }
                }
                .padding(AppDesign.horizontalPadding)
            }
        }
        .task {
            systemMetrics.setDemand(.controlCenter, active: true)
            let showsAudioMixer = controlCenter.controlCenterFeatures.contains { $0.id == .audioMixer }
            audioMixer.setDemand(.controlCenter, active: showsAudioMixer)
            defer {
                systemMetrics.setDemand(.controlCenter, active: false)
                audioMixer.setDemand(.controlCenter, active: false)
            }
            await notes.loadIfNeeded()
            try? await Task.sleep(for: .seconds(31_536_000))
        }
    }

    private var controlCenterToolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Control Center")
                    .font(.title3)
                    .bold()
                Text("Your menu-bar tools in one place")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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

    private var clipboardSummary: String {
        if clipboard.isPrivateMode { return String(localized: "Private Mode is active") }
        if clipboard.isPaused { return String(localized: "Recording is paused") }
        return clipboard.items.count == 1
            ? String(localized: "1 saved item")
            : String(localized: "\(clipboard.items.count) saved items")
    }

    private var notesSummary: String {
        return notes.notes.count == 1
            ? String(localized: "1 saved note")
            : String(localized: "\(notes.notes.count) saved notes")
    }

    private func summary(for id: UtilityFeatureID) -> String {
        switch id {
        case .clipboard: return clipboardSummary
        case .notes: return notesSummary
        case .keyboardCleaning:
            return keyboardCleaning.isActive
                ? String(localized: "Keyboard Cleaning is active")
                : String(localized: "Ready for 60-second cleaning")
        case .scrollReverse:
            return scrollReversal.isActive
                ? String(localized: "Scroll Reverse is active")
                : String(localized: "Native scrolling is unchanged")
        case .systemMonitor:
            let cpu = systemMetrics.snapshot.cpu.totalPercent.formatted(.number.precision(.fractionLength(0)))
            let memory = systemMetrics.snapshot.memory.usedPercent.formatted(.number.precision(.fractionLength(0)))
            let temperature = systemMetrics.snapshot.primaryTemperature.map {
                $0.formatted(.number.precision(.fractionLength(0))) + "°C"
            } ?? "—"
            return "CPU \(cpu)% · RAM \(memory)% · \(temperature)"
        case .audioMixer:
            let activeApps = audioMixer.applications.count(where: \.isProducingOutput)
            return String(localized: "\(activeApps) audio apps · \(audioMixer.browserTabs.count) controlled tabs")
        }
    }

    private func symbol(for descriptor: FeatureDescriptor) -> String {
        switch descriptor.id {
        case .clipboard where clipboard.isPaused: "pause.circle"
        case .keyboardCleaning where keyboardCleaning.isActive: "keyboard.badge.ellipsis.fill"
        case .scrollReverse where scrollReversal.isActive: "arrow.up.arrow.down.circle.fill"
        case .systemMonitor: "gauge.with.dots.needle.67percent"
        case .audioMixer where audioMixer.isEverythingMuted: "speaker.slash.fill"
        default: descriptor.systemImage
        }
    }
}
