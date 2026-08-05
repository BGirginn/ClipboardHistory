import AppKit
import QuickLookUI
import XCTest

@testable import ClipboardHistory

@MainActor
final class QuickLookServiceTests: XCTestCase {
    private var directory: URL!
    private var storage: StorageService!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(
            path: "QuickLookServiceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        storage = StorageService(baseDirectory: directory)
    }

    override func tearDown() async throws {
        await storage.close()
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
        try await super.tearDown()
    }

    func testSystemPanelControllerConfiguresAndClosesBackend() {
        let panel = QLPreviewPanel()
        panel.animationBehavior = .none
        let controller = SystemQuickLookPanelController(panel: panel)
        let service = QuickLookService(panelProvider: { controller })

        controller.present(dataSource: service, delegate: service)

        XCTAssertTrue(panel.dataSource === service)
        XCTAssertTrue(panel.delegate === service)
        XCTAssertEqual(panel.currentPreviewItemIndex, 0)
        controller.orderOut()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(panel.dataSource)
        XCTAssertNil(panel.delegate)
    }

    func testFilePreviewFiltersMissingFilesAndCleansUp() async throws {
        let existing = directory.appending(path: "existing.txt")
        try Data("preview".utf8).write(to: existing)
        let missing = directory.appending(path: "missing.txt")
        let panel = QuickLookPanelControllerSpy()
        let service = QuickLookService(panelProvider: { panel })
        let item = ClipboardItem(
            type: .files,
            hash: "files",
            contentSubtype: .file,
            fileURLs: [existing.path, missing.path]
        )

        service.show(item: item, storage: storage)
        await waitUntil { panel.presentCount == 1 }

        XCTAssertEqual(service.numberOfPreviewItems(in: nil), 1)
        XCTAssertEqual(
            (service.previewPanel(nil, previewItemAt: 0) as? NSURL)?.path,
            existing.path
        )
        XCTAssertNil(service.previewPanel(nil, previewItemAt: 1))
        service.close()
        XCTAssertEqual(panel.orderOutCount, 1)
        XCTAssertEqual(service.numberOfPreviewItems(in: nil), 0)
    }

    func testImageImageGroupPDFAndRichTextAreMaterialized() async throws {
        let panel = QuickLookPanelControllerSpy()
        let service = QuickLookService(panelProvider: { panel })
        let imageData = Data("image-data".utf8)
        let imageID = UUID()
        let storedImageName = await storage.storeImage(imageData, id: imageID)
        let imageName = try XCTUnwrap(storedImageName)
        let missingImage = "missing.png"
        let groupID = UUID()
        let storedGroupName = await storage.storeImage(
            Data("group".utf8),
            id: groupID,
            index: 0
        )
        let groupName = try XCTUnwrap(storedGroupName)
        let pdfID = UUID()
        let storedPDFName = await storage.storePayload(
            Data("pdf".utf8),
            id: pdfID,
            extension: "pdf",
            encrypt: false
        )
        let pdfName = try XCTUnwrap(storedPDFName)
        let richID = UUID()
        let storedRichName = await storage.storePayload(
            Data("rtf".utf8),
            id: richID,
            extension: "rtf",
            encrypt: false
        )
        let richName = try XCTUnwrap(storedRichName)
        let items = [
            ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: imageName,
                hash: "image",
                contentSubtype: .image
            ),
            ClipboardItem(
                id: groupID,
                type: .imageGroup,
                hash: "group",
                contentSubtype: .imageGroup,
                assetFilenames: [groupName, missingImage]
            ),
            ClipboardItem(
                id: pdfID,
                type: .pdf,
                hash: "pdf",
                contentSubtype: .pdf,
                payloadFilename: pdfName
            ),
            ClipboardItem(
                id: richID,
                type: .richText,
                hash: "rich",
                contentSubtype: .rtf,
                payloadFilename: richName
            )
        ]

        for (index, item) in items.enumerated() {
            service.show(item: item, storage: storage)
            await waitUntil { panel.presentCount == index + 1 }
            XCTAssertGreaterThan(service.numberOfPreviewItems(in: nil), 0)
            let url = try XCTUnwrap(
                service.previewPanel(nil, previewItemAt: 0) as? URL
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }

        service.previewPanelWillClose(nil)
        XCTAssertEqual(service.numberOfPreviewItems(in: nil), 0)
    }

    func testEmptyMissingPanelAndMaterializationFailureDoNotPresent() async {
        let panel = QuickLookPanelControllerSpy()
        let service = QuickLookService(panelProvider: { panel })
        service.show(
            item: ClipboardItem(type: .text, text: "text", hash: "text"),
            storage: storage
        )
        await drainTasks()
        XCTAssertEqual(panel.presentCount, 0)

        let noPanel = QuickLookService(panelProvider: { nil })
        let existing = directory.appending(path: "existing.txt")
        try? Data("value".utf8).write(to: existing)
        noPanel.show(
            item: ClipboardItem(
                type: .files,
                hash: "files-no-panel",
                contentSubtype: .file,
                fileURLs: [existing.path]
            ),
            storage: storage
        )
        await drainTasks()
        XCTAssertEqual(noPanel.numberOfPreviewItems(in: nil), 1)

        let payloadID = UUID()
        let filename = await storage.storePayload(
            Data("payload".utf8),
            id: payloadID,
            extension: "pdf",
            encrypt: false
        )
        let failing = QuickLookService(
            panelProvider: { panel },
            temporaryDirectoryProvider: { URL(fileURLWithPath: "/dev/null") }
        )
        failing.show(
            item: ClipboardItem(
                id: payloadID,
                type: .pdf,
                hash: "failing",
                contentSubtype: .pdf,
                payloadFilename: filename
            ),
            storage: storage
        )
        await drainTasks()
        XCTAssertEqual(panel.presentCount, 0)
    }

    private func waitUntil(
        _ predicate: @escaping () -> Bool,
        iterations: Int = 100
    ) async {
        for _ in 0..<iterations where !predicate() {
            await Task.yield()
        }
        XCTAssertTrue(predicate())
    }

    private func drainTasks() async {
        for _ in 0..<100 {
            await Task.yield()
        }
    }
}

@MainActor
private final class QuickLookPanelControllerSpy: QuickLookPanelControlling {
    private(set) var presentCount = 0
    private(set) var orderOutCount = 0

    func present(
        dataSource: any QLPreviewPanelDataSource,
        delegate: any QLPreviewPanelDelegate
    ) {
        presentCount += 1
    }

    func orderOut() {
        orderOutCount += 1
    }
}
