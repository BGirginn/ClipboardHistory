import SwiftUI

struct FileDetailPreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(item.fileURLs, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                        if !FileManager.default.fileExists(atPath: path) {
                            Label("Unavailable", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }
}
