import AppKit
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class HistoryPresentationTests: XCTestCase {
    private var directory: URL!
    private var suite: String!
    private var storage: StorageService!
    private var settings: AppSettings!
    private var pasteboard: NSPasteboard!
    private var viewModel: ClipboardHistoryViewModel!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(
            path: "HistoryPresentationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        suite = "HistoryPresentationDefaults-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.closePanelAfterCopying = false
        storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        pasteboard = NSPasteboard(name: .init("PresentationPasteboard-\(UUID().uuidString)"))
        viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: settings,
            startsAutomatically: false
        )
    }

    override func tearDown() async throws {
        viewModel.prepareForShutdown()
        await storage.close()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        viewModel = nil
        storage = nil
        settings = nil
        pasteboard = nil
        directory = nil
        suite = nil
        try await super.tearDown()
    }

    func testSearchIsCaseInsensitiveWhitespaceTolerantAndOrderPreserving() async {
        await insert("Alpha first note")
        await insert("middle")
        await insert("ALPHA second NOTE")

        viewModel.searchText = " alpha   note "

        XCTAssertEqual(viewModel.recentItems.compactMap(\.text), ["ALPHA second NOTE", "Alpha first note"])
    }

    func testFiltersAndPinnedSection() async throws {
        await insert("text")
        let imageData = try makePNG()
        await viewModel.insert(.image(pngData: imageData, hash: "image"))
        let textItem = try XCTUnwrap(viewModel.items.first { $0.type == .text })
        viewModel.togglePin(textItem)

        XCTAssertEqual(viewModel.pinnedItems.map(\.hash), [textItem.hash])
        settings.selectedFilter = .images
        await Task.yield()
        viewModel.settingsDidChange()
        XCTAssertTrue(viewModel.pinnedItems.isEmpty)
        XCTAssertEqual(viewModel.recentItems.map(\.type), [.image])
        settings.selectedFilter = .pinned
        viewModel.settingsDidChange()
        XCTAssertEqual(viewModel.pinnedItems.map(\.hash), [textItem.hash])
        XCTAssertTrue(viewModel.recentItems.isEmpty)
    }

    func testSortModesAndRecentlyUsedUpdate() async throws {
        await insert("old")
        try? await Task.sleep(for: .milliseconds(10))
        await insert("new")
        settings.selectedSortMode = .oldestFirst
        viewModel.settingsDidChange()
        XCTAssertEqual(viewModel.recentItems.compactMap(\.text), ["old", "new"])

        let old = try XCTUnwrap(viewModel.items.first { $0.text == "old" })
        await viewModel.restoreAndWait(old)
        settings.selectedSortMode = .recentlyUsed
        viewModel.settingsDidChange()
        XCTAssertEqual(viewModel.recentItems.first?.text, "old")
        XCTAssertEqual(viewModel.recentItems.first?.useCount, 1)
    }

    func testKeyboardSelectionAndCopyFeedback() async throws {
        await insert("one")
        await insert("two")
        viewModel.selectedItemID = viewModel.recentItems.first?.id
        viewModel.selectNext()
        XCTAssertEqual(viewModel.selectedItem?.text, "one")
        let selected = try XCTUnwrap(viewModel.selectedItem)

        await viewModel.restoreAndWait(selected)

        XCTAssertEqual(viewModel.copiedItemID, selected.id)
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertNil(viewModel.copiedItemID)
    }

    func testDuplicateScopesAndHistoryLimitExcludePinned() async {
        settings.historyLimit = 10
        settings.duplicateDetectionScope = .lastTen
        for index in 0..<12 { await insert("item \(index)") }
        let newest = viewModel.items[0]
        viewModel.togglePin(newest)
        await insert("item 12")
        XCTAssertEqual(viewModel.items.filter { !$0.isPinned }.count, 10)
        XCTAssertTrue(viewModel.items.contains { $0.id == newest.id && $0.isPinned })
    }

    private func insert(_ text: String) async {
        await viewModel.insert(.text(value: text, hash: HashUtility.sha256(text: text)))
    }

    private func makePNG() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
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
        ))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
