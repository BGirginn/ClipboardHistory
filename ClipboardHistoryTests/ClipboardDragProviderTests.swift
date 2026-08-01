import AppKit
import UniformTypeIdentifiers
import XCTest

@testable import ClipboardHistory

@MainActor
final class ClipboardDragProviderTests: XCTestCase {
    private var directory: URL!
    private var storage: StorageService!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardDragProviderTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = StorageService(baseDirectory: directory)
    }

    override func tearDown() async throws {
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
        try await super.tearDown()
    }

    func testTextRichTextAndFileProviders() throws {
        let text = ClipboardDragProviderFactory.make(
            for: ClipboardItem(type: .text, text: "drag text", hash: "text"),
            storage: storage
        )
        XCTAssertTrue(text.canLoadObject(ofClass: NSString.self))

        let rich = ClipboardDragProviderFactory.make(
            for: ClipboardItem(type: .richText, text: nil, hash: "rich"),
            storage: storage
        )
        XCTAssertTrue(rich.canLoadObject(ofClass: NSString.self))

        let file = directory.appending(path: "drag.txt")
        try Data("file".utf8).write(to: file)
        let fileProvider = ClipboardDragProviderFactory.make(
            for: ClipboardItem(
                type: .files,
                hash: "file",
                contentSubtype: .file,
                fileURLs: [file.path]
            ),
            storage: storage
        )
        XCTAssertFalse(fileProvider.registeredTypeIdentifiers.isEmpty)

        let emptyFileProvider = ClipboardDragProviderFactory.make(
            for: ClipboardItem(type: .files, hash: "empty-file", contentSubtype: .file),
            storage: storage
        )
        XCTAssertTrue(emptyFileProvider.registeredTypeIdentifiers.isEmpty)
    }

    func testImageAndGroupProvidersReturnStoredDataOrReadError() async throws {
        let bytes = Data("png-provider".utf8)
        let id = UUID()
        let storedFilename = await storage.storeImage(bytes, id: id)
        let filename = try XCTUnwrap(storedFilename)
        let valid = ClipboardItem(
            id: id,
            type: .image,
            imageFilename: filename,
            hash: "image",
            contentSubtype: .image
        )
        let provider = SystemClipboardDragProvider().make(for: valid, storage: storage)
        let loaded = await loadData(from: provider, typeIdentifier: UTType.png.identifier)
        XCTAssertEqual(try loaded.get(), bytes)

        let group = ClipboardItem(
            type: .imageGroup,
            hash: "group",
            contentSubtype: .imageGroup,
            assetFilenames: [filename]
        )
        XCTAssertTrue(
            ClipboardDragProviderFactory.make(for: group, storage: storage)
                .hasItemConformingToTypeIdentifier(UTType.png.identifier)
        )

        let missing = ClipboardItem(
            type: .image,
            imageFilename: "missing.png",
            hash: "missing",
            contentSubtype: .image
        )
        let missingResult = await loadData(
            from: ClipboardDragProviderFactory.make(for: missing, storage: storage),
            typeIdentifier: UTType.png.identifier
        )
        XCTAssertThrowsError(try missingResult.get())

        let empty = ClipboardDragProviderFactory.make(
            for: ClipboardItem(type: .image, hash: "empty", contentSubtype: .image),
            storage: storage
        )
        XCTAssertTrue(empty.registeredTypeIdentifiers.isEmpty)
    }

    func testPDFProviderReturnsStoredDataOrReadError() async throws {
        let bytes = Data("pdf-provider".utf8)
        let id = UUID()
        let storedFilename = await storage.storePayload(
            bytes,
            id: id,
            extension: "pdf",
            encrypt: false
        )
        let filename = try XCTUnwrap(storedFilename)
        let provider = ClipboardDragProviderFactory.make(
            for: ClipboardItem(
                id: id,
                type: .pdf,
                hash: "pdf",
                contentSubtype: .pdf,
                payloadFilename: filename
            ),
            storage: storage
        )
        let loaded = await loadData(from: provider, typeIdentifier: UTType.pdf.identifier)
        XCTAssertEqual(try loaded.get(), bytes)

        let missing = ClipboardDragProviderFactory.make(
            for: ClipboardItem(
                type: .pdf,
                hash: "missing-pdf",
                contentSubtype: .pdf,
                payloadFilename: "missing.pdf"
            ),
            storage: storage
        )
        let missingResult = await loadData(
            from: missing,
            typeIdentifier: UTType.pdf.identifier
        )
        XCTAssertThrowsError(try missingResult.get())

        let empty = ClipboardDragProviderFactory.make(
            for: ClipboardItem(type: .pdf, hash: "empty-pdf", contentSubtype: .pdf),
            storage: storage
        )
        XCTAssertTrue(empty.registeredTypeIdentifiers.isEmpty)
    }

    private func loadData(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async -> Result<Data, Error> {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: .success(data))
                } else {
                    continuation.resume(
                        returning: .failure(error ?? CocoaError(.fileReadUnknown))
                    )
                }
            }
        }
    }
}
