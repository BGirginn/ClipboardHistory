import AppKit
import SwiftUI

struct ExcludedApplicationListView: View {
    let bundleIdentifiers: [String]

    var body: some View {
        ForEach(bundleIdentifiers, id: \.self) { bundleIdentifier in
            HStack(spacing: 8) {
                applicationIcon(bundleIdentifier)
                VStack(alignment: .leading, spacing: 1) {
                    Text(applicationName(bundleIdentifier))
                    Text(bundleIdentifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Excluded application, \(applicationName(bundleIdentifier)), \(bundleIdentifier)")
        }
    }

    private func applicationIcon(_ bundleIdentifier: String) -> some View {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private func applicationName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return "Application not installed"
        }
        return FileManager.default.displayName(atPath: url.path)
    }
}
