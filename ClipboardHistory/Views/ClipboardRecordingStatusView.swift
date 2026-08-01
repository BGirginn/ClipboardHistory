import SwiftUI

struct ClipboardRecordingStatusView: View {
    let isPrivateMode: Bool
    let pauseUntil: Date?

    @ViewBuilder
    var body: some View {
        if isPrivateMode {
            Label("Private", systemImage: "eye.slash.fill")
                .foregroundStyle(.orange)
        } else if pauseUntil.map({ $0 > .now }) == true {
            Label("Paused", systemImage: "pause.circle.fill")
                .foregroundStyle(.orange)
        } else {
            Label("Recording", systemImage: "record.circle")
                .foregroundStyle(.secondary)
        }
    }
}
