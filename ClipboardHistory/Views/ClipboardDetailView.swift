import AppKit
import SwiftUI

struct ClipboardDetailView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardHistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left") {
                    viewModel.detailItem = nil
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("detail.back")
                Spacer()
                Text("Item Details")
                    .font(.headline)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { viewModel.restore(item) }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isLocked)
                    .accessibilityIdentifier("detail.copy")
            }
            .padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .accessibilityIdentifier("clipboard.detail")
    }

    @ViewBuilder
    private var preview: some View {
        if viewModel.isLocked || item.isSensitive {
            VStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(item.isSensitive ? "Sensitive Content" : "Clipboard History Locked")
                    .font(.headline)
                Text("The preview is hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            switch item.type {
            case .text, .richText:
                Text(item.text ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
            case .image, .imageGroup, .pdf:
                ClipboardFullPreview(item: item, storage: viewModel.storage)
            case .files:
                FileDetailPreview(item: item)
            }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            if let text = item.text {
                DetailMetadataRow(label: "Characters", value: text.count.formatted())
                DetailMetadataRow(label: "Lines", value: text.components(separatedBy: .newlines).count.formatted())
            }
            if let width = item.imageWidth, let height = item.imageHeight {
                DetailMetadataRow(label: "Dimensions", value: "\(width) × \(height)")
            }
            if let pages = item.pageCount {
                DetailMetadataRow(label: "Pages", value: pages.formatted())
            }
            if let fileSize = item.fileSize {
                DetailMetadataRow(label: "File Size", value: fileSize.formatted(.byteCount(style: .file)))
            }
            DetailMetadataRow(label: "Type", value: item.contentSubtype.rawValue)
            DetailMetadataRow(label: "Created", value: item.creationDate.formatted(date: .long, time: .standard))
            DetailMetadataRow(label: "Last Used", value: item.lastUsedAt?.formatted(date: .long, time: .standard) ?? "Never")
            DetailMetadataRow(label: "Use Count", value: item.useCount.formatted())
            DetailMetadataRow(label: "Hash", value: item.hash)
            if let source = item.sourceApplicationBundleID {
                DetailMetadataRow(label: "Source App", value: source)
            }
            if let path = detailPath {
                DetailMetadataRow(label: "Storage", value: path)
            }
        }
        .font(.caption)
        .textSelection(.enabled)
    }

    private var detailPath: String? {
        if item.type == .files { return item.fileURLs.joined(separator: "\n") }
        if let filename = item.imageFilename ?? item.assetFilenames.first {
            return viewModel.storage.imageURL(filename: filename, isEncrypted: item.isEncrypted).path
        }
        if let filename = item.payloadFilename {
            return viewModel.storage.payloadURL(filename: filename, isEncrypted: item.isEncrypted).path
        }
        return nil
    }
}

private struct DetailMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(5)
                .truncationMode(.middle)
        }
    }
}

private struct ClipboardFullPreview: View {
    let item: ClipboardItem
    let storage: StorageService

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 300)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .task(id: item.id) {
            let data: Data?
            if item.type == .pdf {
                data = nil
            } else if let filename = item.imageFilename ?? item.assetFilenames.first {
                data = await storage.imageData(filename: filename, isEncrypted: item.isEncrypted)
            } else {
                data = nil
            }
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
        }
        .overlay {
            if item.type == .pdf && image == nil {
                Label("Press Space for Quick Look", systemImage: "doc.richtext")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FileDetailPreview: View {
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
