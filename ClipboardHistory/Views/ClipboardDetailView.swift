import AppKit
import SwiftUI

struct ClipboardDetailView: View {
    let item: ClipboardItem
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @State private var draftTitle: String
    @State private var draftText: String
    @State private var draftTags: String
    @State private var selectedCollectionID: UUID?
    @State private var isSnippet: Bool

    init(item: ClipboardItem, viewModel: ClipboardHistoryViewModel) {
        self.item = item
        self.viewModel = viewModel
        _draftTitle = State(initialValue: item.displayTitle ?? "")
        _draftText = State(initialValue: item.text ?? "")
        _draftTags = State(initialValue: item.protectedMetadata.tags.joined(separator: ", "))
        _selectedCollectionID = State(initialValue: item.collectionID)
        _isSnippet = State(initialValue: item.isSnippet)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: goBack)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("detail.back")
                Spacer()
                Text("Item Details")
                    .font(.headline)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc", action: copyItem)
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isLocked)
                    .accessibilityIdentifier("detail.copy")
            }
            .padding(12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    editor
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .accessibilityIdentifier("clipboard.detail")
    }

    private var editor: some View {
        GroupBox("Organize and Edit") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Visible name", text: $draftTitle)
                    .accessibilityIdentifier("detail.title")
                if [.text, .richText].contains(item.type) {
                    TextField("Text", text: $draftText, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("detail.text")
                    Menu("Transform Text", systemImage: "textformat") {
                        ForEach(TextTransformation.allCases) { transformation in
                            ClipboardTextTransformationButton(
                                transformation: transformation,
                                text: $draftText
                            )
                        }
                    }
                    .accessibilityIdentifier("detail.transform")
                }
                TextField("Tags, separated by commas", text: $draftTags)
                    .accessibilityIdentifier("detail.tags")
                Picker("Collection", selection: $selectedCollectionID) {
                    Text("No Collection").tag(UUID?.none)
                    ForEach(viewModel.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
                Toggle("Keep as Snippet", isOn: $isSnippet)
                HStack {
                    Spacer()
                    Button("Save Changes", systemImage: "checkmark", action: saveChanges)
                    .accessibilityIdentifier("detail.save")
                }
            }
            .padding(6)
        }
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
            if let ocr = item.protectedMetadata.extractedText {
                DetailMetadataRow(label: "Recognized Text", value: ocr)
            }
            if let qrCode = item.protectedMetadata.qrCodeText {
                DetailMetadataRow(label: "QR Code", value: qrCode)
            }
            if let color = item.protectedMetadata.colorHex {
                DetailMetadataRow(label: "Color", value: color)
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
            return viewModel.storage.imageURL(
                filename: filename,
                isEncrypted: item.isEncrypted
            )?.path
        }
        if let filename = item.payloadFilename {
            return viewModel.storage.payloadURL(
                filename: filename,
                isEncrypted: item.isEncrypted
            )?.path
        }
        return nil
    }

    func goBack() {
        viewModel.detailItem = nil
    }

    func copyItem() {
        viewModel.restore(item)
    }

    func saveChanges() {
        viewModel.updateItem(
            item,
            title: draftTitle,
            editedText: [.text, .richText].contains(item.type) ? draftText : nil,
            tags: draftTags,
            collectionID: selectedCollectionID,
            isSnippet: isSnippet
        )
    }
}
