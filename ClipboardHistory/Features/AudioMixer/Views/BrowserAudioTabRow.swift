import SwiftUI

struct BrowserAudioTabRow: View {
    let tab: BrowserAudioTab
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    let activate: () -> Void
    let effectiveVolume: Double
    @State private var volume: Double

    init(
        tab: BrowserAudioTab,
        effectiveVolume: Double,
        setVolume: @escaping (Double) -> Void,
        toggleMute: @escaping () -> Void,
        activate: @escaping () -> Void
    ) {
        self.tab = tab
        self.effectiveVolume = effectiveVolume
        self.setVolume = setVolume
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
            if abs(effectiveVolume - volume) > 0.5 {
                Text("Effective volume with browser master: \(effectiveVolume / 100, format: .percent.precision(.fractionLength(0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $volume, in: 0...100, step: 1)
                .accessibilityLabel(String(localized: "Volume for browser tab \(tab.title)"))
                .onChange(of: volume) { _, newValue in setVolume(newValue) }
        }
        .padding(.vertical, 6)
        .onChange(of: tab.volume) { _, newValue in
            if abs(volume - newValue) > 0.5 { volume = newValue }
        }
    }
}
