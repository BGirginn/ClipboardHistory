import XCTest
@testable import ClipboardHistory

final class HashUtilityTests: XCTestCase {
    func testSHA256ForTextUsesUTF8() {
        XCTAssertEqual(
            HashUtility.sha256(text: "hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testTextAndEquivalentDataProduceSameHash() {
        let text = "Clipboard History"
        XCTAssertEqual(
            HashUtility.sha256(text: text),
            HashUtility.sha256(data: Data(text.utf8))
        )
    }
}
