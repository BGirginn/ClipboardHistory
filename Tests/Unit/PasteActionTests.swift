import AppKit
import XCTest

@testable import ClipboardHistory

final class PasteActionTests: XCTestCase {
    @MainActor
    func testPasteRepresentationsWriteOnlyRequestedTypes() async throws {
        let pasteboard = NSPasteboard(name: .init("PasteRepresentations-\(UUID().uuidString)"))
        let writer = ClipboardPasteboardWriter(pasteboard: pasteboard)
        let content = ClipboardContent.text(
            value: "plain",
            rtfData: Data("{\\rtf1 rich}".utf8),
            htmlData: Data("<b>html</b>".utf8),
            subtype: .html,
            hash: "representations",
            sourceBundleIdentifier: nil
        )

        let wroteOriginal = await writer.write(content: content, representation: .original)
        XCTAssertTrue(wroteOriginal)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
        XCTAssertNotNil(pasteboard.data(forType: .html))

        let wrotePlainText = await writer.write(content: content, representation: .plainText)
        XCTAssertTrue(wrotePlainText)
        XCTAssertEqual(pasteboard.string(forType: .string), "plain")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))

        let wroteRichText = await writer.write(content: content, representation: .richText)
        XCTAssertTrue(wroteRichText)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))

        let wroteHTML = await writer.write(content: content, representation: .html)
        XCTAssertTrue(wroteHTML)
        XCTAssertNil(pasteboard.data(forType: .rtf))
        let cleanedHTML = try XCTUnwrap(pasteboard.data(forType: .html))
        XCTAssertNotNil(String(data: cleanedHTML, encoding: .utf8))

        let unsafeContent = ClipboardContent.text(
            value: "safe",
            rtfData: nil,
            htmlData: Data("<b>safe</b><script>steal()</script><img src=\"https://tracker.invalid/pixel\">".utf8),
            subtype: .html,
            hash: "unsafe-html",
            sourceBundleIdentifier: nil
        )
        let wroteSanitizedHTML = await writer.write(
            content: unsafeContent,
            representation: .html
        )
        XCTAssertTrue(wroteSanitizedHTML)
        let sanitized = try XCTUnwrap(pasteboard.data(forType: .html))
        let sanitizedText = try XCTUnwrap(String(data: sanitized, encoding: .utf8))
        XCTAssertTrue(sanitizedText.contains("<b>safe</b>"))
        XCTAssertFalse(sanitizedText.localizedCaseInsensitiveContains("script"))
        XCTAssertFalse(sanitizedText.contains("https://"))
    }

    @MainActor
    func testDirectPasteInvokesAccessibilityServiceButCopyDoesNot() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryDirectPaste-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: .init("DirectPaste-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService()
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: directory),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            startsAutomatically: false
        )
        await viewModel.insert(.text(value: "direct", hash: "direct"))
        let item = try XCTUnwrap(viewModel.items.first)

        await viewModel.restoreAndWait(item)
        XCTAssertEqual(pasteService.pasteCount, 0)
        await viewModel.pasteAndWait(item)
        XCTAssertEqual(pasteService.pasteCount, 1)
        await viewModel.shutdown()
    }

    @MainActor
    func testPermissionIsRequestedOnlyByDirectPasteAndCopyStillSucceeds() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryPastePermission-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: .init("PastePermission-\(UUID().uuidString)"))
        let pasteService = StubActiveApplicationPasteService(result: .permissionRequired)
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: directory),
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            startsAutomatically: false
        )
        await viewModel.insert(.text(value: "permission", hash: "permission"))
        let item = try XCTUnwrap(viewModel.items.first)

        await viewModel.restoreAndWait(item)
        XCTAssertNil(viewModel.errorMessage)
        await viewModel.pasteAndWait(item, as: .plainText)

        XCTAssertEqual(pasteboard.string(forType: .string), "permission")
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(pasteService.pasteCount, 1)
        await viewModel.shutdown()
    }
}
