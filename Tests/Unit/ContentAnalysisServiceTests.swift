import AppKit
import CoreImage
import XCTest

@testable import ClipboardHistory

final class ContentAnalysisServiceTests: XCTestCase {
    func testColorNormalizationAndClassification() {
        XCTAssertEqual(ColorParser.hexColor(from: " #f3a "), "#FF33AA")
        XCTAssertEqual(ColorParser.hexColor(from: "rgb(12, 34, 255)"), "#0C22FF")
        XCTAssertNil(ColorParser.hexColor(from: "rgb(999, 0, 0)"))
        XCTAssertEqual(TextClassifier.subtype(for: "#00AAFF"), .color)
    }

    func testQRCodeAnalysisRunsLocallyWhenOCRIsDisabled() async throws {
        let expected = "clipboardhistory://local/qr-42"
        let pngData = try makeQRCodePNG(expected)
        let content = ClipboardContent.images(
            pngData: [pngData],
            hash: "qr",
            sourceBundleIdentifier: nil
        )

        let analysis = await ClipboardContentAnalysisService().analyze(
            content,
            recognizesImageText: false
        )

        XCTAssertEqual(analysis.qrCodeText, expected)
        XCTAssertNil(analysis.extractedText)
    }

    @MainActor
    func testVisionOCRExtractsSearchableTextOnDevice() async throws {
        let pngData = try makeTextPNG("CLIPBOARD HISTORY 42")
        let content = ClipboardContent.images(
            pngData: [pngData],
            hash: "ocr",
            sourceBundleIdentifier: nil
        )

        let analysis = await ClipboardContentAnalysisService().analyze(
            content,
            recognizesImageText: true
        )

        XCTAssertTrue(analysis.extractedText?.localizedStandardContains("CLIPBOARD") == true)
        XCTAssertTrue(analysis.extractedText?.localizedStandardContains("42") == true)
    }

    private func makeQRCodePNG(_ value: String) throws -> Data {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(value.utf8), forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")
        let image = try XCTUnwrap(filter?.outputImage?.transformed(by: .init(scaleX: 12, y: 12)))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent))
        return try XCTUnwrap(
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        )
    }

    @MainActor
    private func makeTextPNG(_ value: String) throws -> Data {
        let size = NSSize(width: 900, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        value.draw(at: NSPoint(x: 30, y: 70), withAttributes: attributes)
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        )
    }
}
