import Foundation
import XCTest

@testable import ClipboardHistory

final class ClipboardSearchQueryTests: XCTestCase {
    func testFieldFiltersMatchProtectedAndPublicMetadata() {
        let item = ClipboardItem(
            type: .image,
            imageFilename: "image.png",
            creationDate: date(2026, 7, 20),
            hash: "hash",
            displayTitle: "Control panel",
            contentSubtype: .image,
            sourceApplicationBundleID: "com.example.Factory",
            protectedMetadata: ClipboardProtectedMetadata(
                displayTitle: "Control panel",
                tags: ["Urgent"],
                extractedText: "Pressure warning",
                qrCodeText: "machine-42"
            )
        )

        XCTAssertTrue(ClipboardSearchQuery("app:factory type:image tag:urgent").matches(item, collectionName: "Night Shift"))
        XCTAssertTrue(ClipboardSearchQuery("collection:night ocr:pressure qr:machine").matches(item, collectionName: "Night Shift"))
        XCTAssertTrue(ClipboardSearchQuery("after:2026-07-01 before:2026-08-01").matches(item, collectionName: nil))
        XCTAssertFalse(ClipboardSearchQuery("app:factory tag:missing").matches(item, collectionName: "Night Shift"))
        XCTAssertFalse(ClipboardSearchQuery("before:2026-07-01").matches(item, collectionName: nil))
        XCTAssertFalse(ClipboardSearchQuery("after:not-a-date").matches(item, collectionName: nil))
    }

    func testUnknownPrefixRemainsAFreeTextTerm() {
        let item = ClipboardItem(type: .text, text: "owner:local", hash: "hash")
        XCTAssertTrue(ClipboardSearchQuery("owner:local").matches(item, collectionName: nil))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }
}
