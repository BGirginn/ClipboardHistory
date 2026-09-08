import SwiftUI

struct BrowserAudioTabRow: View {
    let tab: BrowserAudioTab
    let previewVolume: (Double) -> Void
    let commitVolume: (Double) -> Void
    let toggleMute: () -> Void
    let activate: () -> Void
    let effectiveVolume: Double
    @State private var volume: Double
    @State private var isEditingVolume = false

    init(
        tab: BrowserAudioTab,
        effectiveVolume: Double,
        previewVolume: @escaping (Double) -> Void,
        commitVolume: @escaping (Double) -> Void,
        toggleMute: @escaping () -> Void,
        activate: @escaping () -> Void
    ) {
        self.tab = tab
        self.effectiveVolume = effectiveVolume
        self.previewVolume = previewVolume
        self.commitVolume = commitVolume
        self.toggleMute = toggleMute
        self.activate = activate
        _volume = State(initialValue: tab.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(tab.title).lineLimit(1)
                    Text(tab.browser).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(volume / 100, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
                Button(
                    tab.isMuted ? "Unmute Tab" : "Mute Tab",
                    systemImage: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    action: toggleMute
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                Button("Go to Tab", systemImage: "arrow.up.right.square", action: activate)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
                Text("Effective volume with browser master: \(effectiveVolume / 100, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            Slider(value: $volume, in: 0...100, step: 1) { editing in
                isEditingVolume = editing
                if !editing { commitVolume(volume) }
            }
                .accessibilityLabel(String(localized: "Volume for browser tab \(tab.title)"))
                .onChange(of: volume) { _, newValue in
                    if isEditingVolume { previewVolume(newValue) }
                }
        }
        .padding(.vertical, 6)
        .onChange(of: tab.volume) { _, newValue in
            if !isEditingVolume, abs(volume - newValue) > 0.5 { volume = newValue }
        }
    }
}
