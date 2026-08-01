import AppKit
import PDFKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardPanelRenderingTests: XCTestCase {
    func testEmptyPanelRendersAtRequestedSize() async {
        let context = makeContext()
        let hostingView = NSHostingView(
            rootView: ClipboardPanelView(viewModel: context.viewModel)
        )

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.width, 380, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, 500, accuracy: 0.5)
        await cleanup(context)
    }

    func testPanelAndProblematicSettingsStatesRender() async throws {
        let context = makeContext()
        do {
            context.viewModel.setPrivateModeEnabled(true)
            context.viewModel.lockService.configure(
                enabled: true,
                option: .never
            )
            context.viewModel.lock()
            try render(
                ClipboardPanelView(viewModel: context.viewModel),
                named: "panel-private-locked-light",
                colorScheme: .light
            )

            for (index, section) in ClipboardSettingsSection.allCases.enumerated() {
                let colorScheme: ColorScheme = index.isMultiple(of: 2) ? .light : .dark
                try render(
                    ClipboardSettingsView(
                        viewModel: context.viewModel,
                        initialSection: section
                    )
                    .frame(width: 380, height: 500),
                    named: "settings-\(section.rawValue)-\(colorScheme == .dark ? "dark" : "light")",
                    colorScheme: colorScheme
                )
            }
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    func testStandaloneViewBranchMatrixRenders() async throws {
        let context = makeContext()
        do {
            let png = try makePNG()
            let imageID = UUID()
            let storedImageFilename = await context.storage.storeImage(png, id: imageID)
            let imageFilename = try XCTUnwrap(storedImageFilename)
            let groupID = UUID()
            let storedGroupFilename = await context.storage.storeImage(png, id: groupID, index: 0)
            let groupFilename = try XCTUnwrap(storedGroupFilename)
            let pdf = try makePDF(from: png)
            let pdfID = UUID()
            let storedPDFFilename = await context.storage.storePayload(
                pdf,
                id: pdfID,
                extension: "pdf",
                encrypt: false
            )
            let pdfFilename = try XCTUnwrap(storedPDFFilename)
            let existingFile = context.directory.appending(path: "available.txt")
            try Data("available".utf8).write(to: existingFile)
            let missingFile = context.directory.appending(path: "missing.txt")
            let metadata = ClipboardProtectedMetadata(
                displayTitle: "Metadata title",
                tags: ["tag"],
                extractedText: "recognized",
                qrCodeText: "qr",
                colorHex: "#112233"
            )
            let text = ClipboardItem(
                type: .text,
                text: "First line\nSecond line",
                hash: "render-text",
                lastUsedAt: .now,
                useCount: 2,
                displayTitle: "Text title",
                contentSubtype: .plainText,
                sourceApplicationBundleID: "com.example.source",
                fileSize: 22,
                protectedMetadata: metadata
            )
            let rich = ClipboardItem(
                type: .richText,
                text: "Rich text",
                hash: "render-rich",
                contentSubtype: .rtf
            )
            let image = ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: imageFilename,
                hash: "render-image",
                displayTitle: "Image title",
                thumbnailFilename: "\(imageID.uuidString.lowercased())-thumb.png",
                contentSubtype: .image,
                imageWidth: 24,
                imageHeight: 16,
                fileSize: Int64(png.count)
            )
            let imageGroup = ClipboardItem(
                id: groupID,
                type: .imageGroup,
                hash: "render-group",
                contentSubtype: .imageGroup,
                assetFilenames: [groupFilename]
            )
            let pdfItem = ClipboardItem(
                id: pdfID,
                type: .pdf,
                hash: "render-pdf",
                contentSubtype: .pdf,
                payloadFilename: pdfFilename,
                pageCount: 1,
                fileSize: Int64(pdf.count)
            )
            let files = ClipboardItem(
                type: .files,
                hash: "render-files",
                contentSubtype: .file,
                fileURLs: [existingFile.path, missingFile.path]
            )
            let filesWithoutURL = ClipboardItem(
                type: .files,
                hash: "render-files-empty",
                contentSubtype: .file
            )
            let sensitiveImage = ClipboardItem(
                type: .image,
                imageFilename: "missing.png",
                hash: "render-sensitive",
                contentSubtype: .image,
                isSensitive: true
            )
            let missingImage = ClipboardItem(
                type: .image,
                imageFilename: "missing.png",
                hash: "render-missing-image",
                contentSubtype: .image
            )

            context.viewModel.items = [text, rich, image, imageGroup, pdfItem, files]
            context.viewModel.collections = [ClipboardCollection(name: "Render Collection")]
            context.viewModel.selectedItemIDs = [text.id, image.id]
            context.viewModel.refreshDisplayedItems()
            context.viewModel.errorMessage = "Keychain unavailable"
            context.viewModel.archiveStatusMessage = "Recovery ready"

            let actions = ClipboardItemActions(
                selectAndCopy: { _ in },
                copy: { _ in },
                paste: { _ in },
                copyAs: { _, _ in },
                pasteAs: { _, _ in },
                togglePin: { _ in },
                toggleSnippet: { _ in },
                moveToCollection: { _, _ in },
                collections: context.viewModel.collections,
                addToPasteStack: { _ in },
                removeFromPasteStack: { _ in },
                pasteStackItemIDs: [text.id],
                dragProvider: { _ in NSItemProvider() },
                showDetails: { _ in },
                reveal: { _ in },
                exportImage: { _, _ in },
                delete: { _ in },
                menuCommandDidRun: {}
            )

            try render(ClipboardBulkActionsView(viewModel: context.viewModel), named: "bulk-actions", colorScheme: .light)
            try render(ClipboardFilteredEmptyStateView(hasSearch: true), named: "empty-search", colorScheme: .dark)
            try render(ClipboardFilteredEmptyStateView(hasSearch: false), named: "empty-filter", colorScheme: .light)
            try render(ClipboardFullPreview(item: image, storage: context.storage), named: "full-image", colorScheme: .dark)
            try render(ClipboardFullPreview(item: pdfItem, storage: context.storage), named: "full-pdf", colorScheme: .light)
            try render(
                ClipboardImageThumbnail(
                    item: image,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    isLocked: false
                ),
                named: "thumbnail-image",
                colorScheme: .light
            )
            try render(
                ClipboardImageThumbnail(
                    item: sensitiveImage,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    isLocked: false
                ),
                named: "thumbnail-sensitive",
                colorScheme: .dark
            )
            try render(
                ClipboardImageThumbnail(
                    item: missingImage,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    isLocked: false
                ),
                named: "thumbnail-missing",
                colorScheme: .light
            )
            for (index, item) in [text, rich, image, imageGroup, pdfItem, files].enumerated() {
                try render(
                    ClipboardItemRowContent(
                        item: item,
                        storage: context.storage,
                        thumbnailService: context.viewModel.thumbnailService,
                        isLocked: index.isMultiple(of: 2)
                    ),
                    named: "row-content-\(index)",
                    colorScheme: index.isMultiple(of: 2) ? .dark : .light
                )
            }
            try render(ClipboardStorageRecoveryView(viewModel: context.viewModel), named: "storage-recovery", colorScheme: .dark)
            try render(
                DocumentClipboardItemRow(
                    item: filesWithoutURL,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    isLocked: false
                ),
                named: "document-no-url",
                colorScheme: .light
            )
            try render(FileDetailPreview(item: files), named: "file-detail", colorScheme: .dark)
            try render(
                ImageClipboardItemRow(
                    item: imageGroup,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    isLocked: false
                ),
                named: "image-group-row",
                colorScheme: .light
            )
            try render(ClipboardDetailView(item: text, viewModel: context.viewModel), named: "detail-text", colorScheme: .dark)
            try render(ClipboardDetailView(item: sensitiveImage, viewModel: context.viewModel), named: "detail-sensitive", colorScheme: .light)
            try render(ClipboardDetailView(item: image, viewModel: context.viewModel), named: "detail-image", colorScheme: .dark)
            try render(ClipboardDetailView(item: pdfItem, viewModel: context.viewModel), named: "detail-pdf", colorScheme: .light)
            try render(ClipboardDetailView(item: files, viewModel: context.viewModel), named: "detail-files", colorScheme: .dark)
            context.viewModel.pasteStackItemIDs = [text.id, rich.id]
            try render(ClipboardPasteStackView(viewModel: context.viewModel), named: "paste-stack-fifo", colorScheme: .light)
            context.viewModel.settings.pasteStackOrder = .lifo
            try render(ClipboardPasteStackView(viewModel: context.viewModel), named: "paste-stack-lifo", colorScheme: .dark)
            var searchValue = "search"
            try render(
                ClipboardSearchField(
                    text: Binding(
                        get: { searchValue },
                        set: { searchValue = $0 }
                    ),
                    focusRequest: 1,
                    focusChanged: { _ in }
                ),
                named: "search-field-filled",
                colorScheme: .light
            )
            searchValue = ""
            try render(
                ClipboardSearchField(
                    text: Binding(get: { searchValue }, set: { searchValue = $0 }),
                    focusRequest: 2,
                    focusChanged: { _ in }
                ),
                named: "search-field-empty",
                colorScheme: .dark
            )
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: false,
                    pinnedItems: [text],
                    recentItems: [rich, image, files],
                    selectedItemID: text.id,
                    selectedItemIDs: [text.id, rich.id],
                    copiedItemID: text.id,
                    hasSearch: false,
                    isLocked: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: true
                ),
                named: "history-list-sections",
                colorScheme: .light
            )
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: true,
                    pinnedItems: [],
                    recentItems: [],
                    selectedItemID: nil,
                    selectedItemIDs: [],
                    copiedItemID: nil,
                    hasSearch: false,
                    isLocked: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: false
                ),
                named: "history-list-empty",
                colorScheme: .dark
            )
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: false,
                    pinnedItems: [],
                    recentItems: [],
                    selectedItemID: nil,
                    selectedItemIDs: [],
                    copiedItemID: nil,
                    hasSearch: true,
                    isLocked: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: false
                ),
                named: "history-list-filtered-empty",
                colorScheme: .light
            )
            try render(
                ClipboardItemRow(
                    item: text,
                    isSelected: true,
                    isCopied: true,
                    isLocked: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions
                ),
                named: "item-row-selected-copied",
                colorScheme: .dark
            )
            var pinned = text
            pinned.isPinned = true
            pinned.isEncrypted = true
            try render(
                ClipboardItemRow(
                    item: pinned,
                    isSelected: false,
                    isCopied: false,
                    isLocked: true,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions
                ),
                named: "item-row-pinned-locked",
                colorScheme: .light
            )
            try render(
                ClipboardItemContextMenu(item: image, actions: actions),
                named: "item-context-menu-image",
                colorScheme: .dark
            )
            try render(
                ClipboardItemContextMenu(item: text, actions: actions),
                named: "item-context-menu-text",
                colorScheme: .light
            )

            context.viewModel.detailItem = text
            try render(ClipboardPanelView(viewModel: context.viewModel), named: "panel-detail", colorScheme: .dark)
            context.viewModel.detailItem = nil
            context.viewModel.isShowingSettings = true
            try render(ClipboardPanelView(viewModel: context.viewModel), named: "panel-settings", colorScheme: .light)
            context.viewModel.isShowingSettings = false
            context.viewModel.isStorageAvailable = false
            try render(ClipboardPanelView(viewModel: context.viewModel), named: "panel-storage-failure", colorScheme: .dark)
            context.viewModel.isStorageAvailable = true

            context.viewModel.isPrivateMode = true
            context.viewModel.privateModeUntil = .now.addingTimeInterval(60)
            try render(ClipboardPanelStatusView(viewModel: context.viewModel), named: "status-private", colorScheme: .light)
            context.viewModel.isPrivateMode = false
            context.viewModel.privateModeUntil = nil
            context.viewModel.pauseUntil = .now.addingTimeInterval(60)
            try render(ClipboardPanelStatusView(viewModel: context.viewModel), named: "status-paused", colorScheme: .dark)
            context.viewModel.pauseUntil = nil
            context.viewModel.lockService.configure(enabled: true, option: .never, startsLocked: true)
            try render(ClipboardPanelHeaderView(viewModel: context.viewModel), named: "header-locked", colorScheme: .light)
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    private func render<Content: View>(
        _ content: Content,
        named name: String,
        colorScheme: ColorScheme
    ) throws {
        let hostingView = NSHostingView(
            rootView: content.environment(\.colorScheme, colorScheme)
        )
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        XCTAssertEqual(representation.pixelsWide, 760, accuracy: 2)
        XCTAssertEqual(representation.pixelsHigh, 1_000, accuracy: 2)

        let outputDirectory = ProcessInfo.processInfo.environment[
            "CLIPBOARD_HISTORY_RENDER_OUTPUT"
        ] ?? "/tmp/ClipboardHistoryUI"
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let png = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        try png.write(
            to: directory.appending(path: "\(name).png"),
            options: .atomic
        )
    }

    private struct Context {
        let directory: URL
        let defaultsSuite: String
        let storage: StorageService
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext() -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardPanelRenderingTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let pasteboard = NSPasteboard(
            name: .init("PanelRenderingTests-\(UUID().uuidString)")
        )
        let defaultsSuite = "PanelRenderingDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let storage = StorageService(baseDirectory: directory)
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            defaultsSuite: defaultsSuite,
            storage: storage,
            viewModel: viewModel
        )
    }

    private func cleanup(_ context: Context) async {
        context.viewModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func makePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 16).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func makePDF(from png: Data) throws -> Data {
        let image = try XCTUnwrap(NSImage(data: png))
        let page = try XCTUnwrap(PDFPage(image: image))
        let document = PDFDocument()
        document.insert(page, at: 0)
        return try XCTUnwrap(document.dataRepresentation())
    }
}
