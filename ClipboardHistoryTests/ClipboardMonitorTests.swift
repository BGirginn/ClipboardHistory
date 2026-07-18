import AppKit
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardMonitorTests: XCTestCase, ClipboardMonitorDelegate {
    private var pasteboard: NSPasteboard!
    private var monitor: ClipboardMonitor!
    private var receivedContent: ClipboardContent?

    private func prepareMonitor() {
        pasteboard = NSPasteboard(name: .init("ClipboardMonitorTests-\(UUID().uuidString)"))
        monitor = ClipboardMonitor(pasteboard: pasteboard)
        monitor.delegate = self
        receivedContent = nil
    }

    func testPollingIntervalIsHalfASecond() {
        XCTAssertEqual(ClipboardMonitor.pollingInterval, 0.5)
    }

    func testMonitorDoesNotRetainItselfThroughTimer() {
        weak var weakMonitor: ClipboardMonitor?

        autoreleasepool {
            var instance: ClipboardMonitor? = ClipboardMonitor(
                pasteboard: NSPasteboard(name: .init("MonitorLifetimeTests"))
            )
            weakMonitor = instance
            instance?.start()
            instance = nil
        }

        XCTAssertNil(weakMonitor)
    }

    func testReadsTextClipboardContent() async {
        prepareMonitor()
        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)

        await monitor.pollNowAndWait()

        guard case let .text(value, _, _, subtype, hash, _) = receivedContent else {
            return XCTFail("Expected text clipboard content")
        }
        XCTAssertEqual(value, "copied text")
        XCTAssertEqual(subtype, .plainText)
        XCTAssertEqual(hash, HashUtility.sha256(text: "copied text"))
    }

    func testPrefersPNGOverText() async throws {
        prepareMonitor()
        let pngData = try XCTUnwrap(makePNGData())
        pasteboard.clearContents()
        pasteboard.setString("lower priority", forType: .string)
        pasteboard.setData(pngData, forType: .png)

        await monitor.pollNowAndWait()

        guard case let .images(images, hash, _) = receivedContent else {
            return XCTFail("Expected image clipboard content")
        }
        XCTAssertEqual(images, [pngData])
        XCTAssertEqual(hash, HashUtility.sha256(data: pngData))
    }

    func testConvertsTIFFClipboardContentToPNG() async throws {
        prepareMonitor()
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor(deviceRed: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)

        pasteboard.clearContents()
        pasteboard.setData(tiffData, forType: .tiff)
        await monitor.pollNowAndWait()

        guard case let .images(pngDataGroup, hash, _) = receivedContent,
              let pngData = pngDataGroup.first else {
            return XCTFail("Expected converted image clipboard content")
        }
        XCTAssertTrue(pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(hash, HashUtility.sha256(data: pngData))
    }

    func clipboardMonitor(_ monitor: ClipboardMonitor, didReceive content: ClipboardContent) {
        receivedContent = content
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
            NSColor(deviceRed: 0.1, green: 0.8, blue: 0.2, alpha: 1),
            atX: 0,
            y: 0
        )
        return bitmap.representation(using: .png, properties: [:])
    }
}
