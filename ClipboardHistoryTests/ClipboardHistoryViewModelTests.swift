import AppKit
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardHistoryViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: StorageService!
    private var monitor: ClipboardMonitor!
    private var pasteboard: NSPasteboard!
    private var viewModel: ClipboardHistoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryViewModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        storage = StorageService(baseDirectory: temporaryDirectory)
        pasteboard = NSPasteboard(name: .init("ClipboardHistoryTests-\(UUID().uuidString)"))
        monitor = ClipboardMonitor(pasteboard: pasteboard)
        viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: monitor,
            restorePasteboard: pasteboard,
            startsAutomatically: false
        )
    }

    override func tearDown() async throws {
        viewModel?.stopMonitoring()
        viewModel = nil
        monitor = nil
        pasteboard = nil
        await storage?.close()
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try await super.tearDown()
    }

    func testDuplicateNewestItemIsIgnored() async {
        let content = ClipboardContent.text(value: "same", hash: HashUtility.sha256(text: "same"))

        await viewModel.insert(content)
        await viewModel.insert(content)

        XCTAssertEqual(viewModel.items.count, 1)
    }

    func testHistoryIsLimitedToOneHundredItems() async {
        for index in 0...StorageService.maximumHistoryCount {
            let value = "item \(index)"
            await viewModel.insert(
                .text(value: value, hash: HashUtility.sha256(text: value))
            )
        }

        XCTAssertEqual(viewModel.items.count, StorageService.maximumHistoryCount)
        XCTAssertEqual(viewModel.items.first?.text, "item 100")
        XCTAssertEqual(viewModel.items.last?.text, "item 1")
    }

    func testClearRemovesHistoryAndPersistsEmptyState() async {
        await viewModel.insert(.text(value: "temporary", hash: "temporary-hash"))

        await viewModel.clearHistoryNow()

        let persistedHistory = await storage.loadHistory()
        XCTAssertTrue(viewModel.items.isEmpty)
        XCTAssertTrue(persistedHistory.isEmpty)
    }

    func testHistoryPersistsAcrossViewModels() async {
        await viewModel.insert(.text(value: "persistent", hash: "persistent-hash"))

        let reloaded = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: NSPasteboard(name: .init("ReloadTests"))),
            restorePasteboard: pasteboard,
            startsAutomatically: false
        )
        await reloaded.loadHistory()

        XCTAssertEqual(reloaded.items.first?.text, "persistent")
    }

    func testProgrammaticTextRestoreDoesNotCreateAnotherItem() async throws {
        let text = "restore me"
        let hash = HashUtility.sha256(text: text)
        await viewModel.insert(.text(value: text, hash: hash))
        let item = try XCTUnwrap(viewModel.items.first)

        await viewModel.restoreAndWait(item)
        await viewModel.insert(.text(value: text, hash: hash))

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    func testProgrammaticImageRestoreWritesPNGAndDoesNotCreateAnotherItem() async throws {
        let data = try XCTUnwrap(makePNGData())
        let hash = HashUtility.sha256(data: data)
        await viewModel.insert(.image(pngData: data, hash: hash))
        let item = try XCTUnwrap(viewModel.items.first)
        let filename = try XCTUnwrap(item.imageFilename)

        await viewModel.restoreStoredImage(filename: filename, hash: hash)
        await viewModel.insert(.image(pngData: data, hash: hash))

        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(pasteboard.data(forType: .png), data)
    }

    private func makePNGData() -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 8,
            bitsPerPixel: 32
        ) else { return nil }

        bitmap.setColor(
            NSColor(deviceRed: 0.5, green: 0.2, blue: 0.8, alpha: 1),
            atX: 0,
            y: 0
        )
        return bitmap.representation(using: .png, properties: [:])
    }
}
