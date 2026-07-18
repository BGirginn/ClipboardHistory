import SwiftUI

struct ClipboardPanelStatusView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.isLocked {
                Label("Locked", systemImage: "lock.fill")
            }

            if viewModel.isPrivateMode {
                Label {
                    HStack(spacing: 4) {
                        Text("Private Mode")
                        if let expiration = viewModel.privateModeUntil {
                            Text(expiration, style: .timer)
                                .monospacedDigit()
                        }
                    }
                } icon: {
                    Image(systemName: "eye.slash.fill")
                }
            } else if let expiration = viewModel.pauseUntil, expiration > .now {
                Label {
                    HStack(spacing: 4) {
                        Text("Paused")
                        Text(expiration, style: .timer)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "pause.circle.fill")
                }
            }

            Spacer(minLength: 0)

            if viewModel.isPrivateMode || viewModel.pauseUntil.map({ $0 > .now }) == true {
                Button("Resume", systemImage: "play.fill", action: viewModel.resumeRecording)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("header.resume")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("header.status")
    }
}
