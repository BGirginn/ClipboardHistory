import SwiftUI

struct OpenInWindowButton: View {
    @Environment(\.applicationPresentation) private var presentation

    var body: some View {
        if !presentation.isWindow, let openWindow = presentation.openWindow {
            Button("Open in Window", systemImage: "arrow.up.forward.app", action: openWindow)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
                .help("Open in Window")
                .accessibilityIdentifier("module.openWindow")
        }
    }
}
