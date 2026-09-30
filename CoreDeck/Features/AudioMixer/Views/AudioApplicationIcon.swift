import AppKit
import SwiftUI

struct AudioApplicationIcon: View {
    let applicationURL: URL?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
        .task(id: applicationURL) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            icon = applicationURL.map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }
        }
    }
}
