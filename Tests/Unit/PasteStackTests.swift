import AppKit
import Combine
import Foundation
import XCTest

@testable import ClipboardHistoryTestHost

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
        let expired = expectation(description: "Paste stack expires using the injected clock")
        let observation = fixture.viewModel.$pasteStackItemIDs
            .dropFirst().first(where: { $0.isEmpty }).sink { _ in expired.fulfill() }
        fixture.viewModel.addToPasteStack(try XCTUnwrap(fixture.viewModel.items.first))
        await fulfillment(of: [expired], timeout: 2)
        observation.cancel()
        XCTAssertTrue(fixture.viewModel.pasteStackItemIDs.isEmpty)
    }

    @MainActor
    private func makeFixture(
        clock: any SleepClock = SystemSleepClock()
    ) throws -> (
        viewModel: ClipboardHistoryViewModel,
        pasteboard: NSPasteboard,
        pasteService: StubActiveApplicationPasteService,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryPasteStack-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let pasteboard = NSPasteboard(name: .init("PasteStack-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService()
        let suite = "PasteStackTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: directory),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            settings: AppSettings(defaults: defaults),
            sleepClock: clock,
            startsAutomatically: false
        )
        addTeardownBlock { @MainActor in
            let stopped = await viewModel.shutdown()
            XCTAssertTrue(stopped, "Pending clipboard writes must finish before fixture removal")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            if stopped {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return (viewModel, pasteboard, pasteService, directory)
    }
}
