import SwiftUI

struct AudioApplicationRow: View {
    let application: AudioApplication
    let setVolume: (Double) -> Void
    let toggleMute: () -> Void
    @State private var volume: Double

    init(
        application: AudioApplication,
        setVolume: @escaping (Double) -> Void,
        toggleMute: @escaping () -> Void
    ) {
        self.application = application
        self.setVolume = setVolume
        self.toggleMute = toggleMute
        _volume = State(initialValue: application.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(application.name, systemImage: application.isProducingOutput ? "speaker.wave.2" : "speaker")
                    .lineLimit(1)
                Spacer()
                Text(volume / 100, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(
                    application.isMuted ? "Unmute" : "Mute",
                    systemImage: application.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    action: toggleMute
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Slider(value: $volume, in: 0...100, step: 1)
                .accessibilityLabel(String(localized: "Volume for \(application.name)"))
                .onChange(of: volume) { _, newValue in setVolume(newValue) }
            if case let .failed(message) = application.controlState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: application.volume) { _, newValue in
            if abs(volume - newValue) > 0.5 { volume = newValue }
        }
    }
}
