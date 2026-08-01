import AppKit
import Foundation
import XCTest

@testable import ClipboardHistory

private struct ImmediateSleepClock: SleepClock {
    func sleep(for duration: Duration) async throws {}
}

final class PasteStackTests: XCTestCase {
    @MainActor
    func testFIFOAndLIFOSequentialPasteRemoveOnlySuccessfullyUsedItem() async throws {
        let fixture = try makeFixture()
        let viewModel = fixture.viewModel
        await viewModel.insert(.text(value: "first", hash: "first"))
        await viewModel.insert(.text(value: "second", hash: "second"))
        let first = try XCTUnwrap(viewModel.items.first(where: { $0.text == "first" }))
        let second = try XCTUnwrap(viewModel.items.first(where: { $0.text == "second" }))
        viewModel.addToPasteStack(first)
        viewModel.addToPasteStack(second)

        viewModel.settings.pasteStackOrder = .fifo
        await viewModel.pasteNextStackItemAndWait()
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "first")
        XCTAssertEqual(viewModel.pasteStackItemIDs, [second.id])

        viewModel.addToPasteStack(first)
        viewModel.settings.pasteStackOrder = .lifo
        await viewModel.pasteNextStackItemAndWait()
        XCTAssertEqual(fixture.pasteboard.string(forType: .string), "first")
        XCTAssertEqual(viewModel.pasteStackItemIDs, [second.id])

        fixture.pasteService.result = .permissionRequired
        await viewModel.pasteNextStackItemAndWait()
        XCTAssertEqual(viewModel.pasteStackItemIDs, [second.id])
        viewModel.resetPasteStack()
        XCTAssertTrue(viewModel.pasteStackItemIDs.isEmpty)
    }

    @MainActor
    func testPasteStackTimeoutUsesInjectedClock() async throws {
        let fixture = try makeFixture(clock: ImmediateSleepClock())
        fixture.viewModel.settings.pasteStackTimeoutMinutes = 1
        await fixture.viewModel.insert(.text(value: "timeout", hash: "timeout"))
        fixture.viewModel.addToPasteStack(try XCTUnwrap(fixture.viewModel.items.first))
        for _ in 0..<10 where !fixture.viewModel.pasteStackItemIDs.isEmpty {
            await Task.yield()
        }
        XCTAssertTrue(fixture.viewModel.pasteStackItemIDs.isEmpty)
    }

    @MainActor
    private func makeFixture(
        clock: any SleepClock = SystemSleepClock()
    ) throws -> (
        viewModel: ClipboardHistoryViewModel,
        pasteboard: NSPasteboard,
        pasteService: StubActiveApplicationPasteService
    ) {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryPasteStack-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let pasteboard = NSPasteboard(name: .init("PasteStack-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService()
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: directory),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            sleepClock: clock,
            startsAutomatically: false
        )
        return (viewModel, pasteboard, pasteService)
    }
}
