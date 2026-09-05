import SwiftUI

struct AudioApplicationRow: View {
    let application: AudioApplication
    let previewVolume: (Double) -> Void
    let commitVolume: (Double) -> Void
    let toggleMute: () -> Void
    @State private var volume: Double
    @State private var isEditingVolume = false

    init(
        application: AudioApplication,
        previewVolume: @escaping (Double) -> Void,
        commitVolume: @escaping (Double) -> Void,
        toggleMute: @escaping () -> Void
    ) {
        self.application = application
        self.previewVolume = previewVolume
        self.commitVolume = commitVolume
        self.toggleMute = toggleMute
        _volume = State(initialValue: application.volume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AudioApplicationIcon(applicationURL: application.applicationURL)
                Text(application.name)
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
            Slider(value: $volume, in: 0...100, step: 1) { editing in
                isEditingVolume = editing
                if !editing { commitVolume(volume) }
            }
                .accessibilityLabel(String(localized: "Volume for \(application.name)"))
                .onChange(of: volume) { _, newValue in
                    if isEditingVolume { previewVolume(newValue) }
                }
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
