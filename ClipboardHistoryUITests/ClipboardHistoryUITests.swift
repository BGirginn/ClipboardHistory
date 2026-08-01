import XCTest

@MainActor
final class ClipboardHistoryUITests: XCTestCase {
    func testSearchSettingsAndIgnoreNextCopyAreKeyboardAccessible() {
        let application = launchApplication()
        defer { application.terminate() }
        let search = application.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.click()
        search.typeText("Alpha")
        let filteredRows = application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'")
        )
        XCTAssertEqual(filteredRows.count, 1)
        XCTAssertTrue(application.buttons["Clear Search"].exists)
        application.buttons["Clear Search"].click()

        application.buttons["Ignore Next Copy"].click()
        application.buttons["Open Settings"].click()
        XCTAssertTrue(application.staticTexts["Settings"].waitForExistence(timeout: 2))
    }

    func testContextMenuOpensDetailsWithoutClosingPanel() {
        let application = launchApplication()
        defer { application.terminate() }
        let rows = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'"))
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        rows.element(boundBy: 0).rightClick()
        application.menuItems["Show Details"].click()
        XCTAssertTrue(application.staticTexts["Item Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["clipboard.panel"].exists)
    }

    func testPasteStackCanBeBuiltAndResetFromContextMenu() {
        let application = launchApplication()
        defer { application.terminate() }
        let firstRow = rows(in: application).element(boundBy: 0)
        firstRow.rightClick()
        let addToPasteStack = application.menuItems["Add to Paste Stack"]
        XCTAssertTrue(addToPasteStack.waitForExistence(timeout: 2))
        // SwiftUI context-menu items are exposed with a valid frame but as
        // non-hittable on macOS 26. Click the center of that exposed frame so
        // the test still exercises the real context-menu action.
        addToPasteStack.hover()
        addToPasteStack.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()

        XCTAssertTrue(application.staticTexts["Paste Stack: 1"].waitForExistence(timeout: 2))
        let reset = application.buttons["Reset Paste Stack"]
        XCTAssertTrue(reset.exists)
        reset.click()
        XCTAssertFalse(application.staticTexts["Paste Stack: 1"].waitForExistence(timeout: 1))
    }

    func testPrivateModeCanBeEnteredAndExitedWithoutLosingHistory() {
        let application = launchApplication()
        defer { application.terminate() }
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)

        application.buttons["Enable Private Mode"].click()
        XCTAssertTrue(application.staticTexts["Private Mode"].waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)
        application.buttons["Disable Private Mode"].click()
        XCTAssertFalse(application.staticTexts["Private Mode"].waitForExistence(timeout: 1))
    }

    func testCommandNumberRestoresVisibleItem() {
        let application = launchApplication()
        defer { application.terminate() }
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)
        let secondRow = rows(in: application).element(boundBy: 1)

        application.typeKey("2", modifierFlags: .command)
        let selected = NSPredicate(format: "value CONTAINS[c] 'selected'")
        expectation(for: selected, evaluatedWith: secondRow)
        waitForExpectations(timeout: 2)
    }

    func testTurkishCorePanelLocalizationLoads() {
        let application = launchApplication(language: "tr")
        defer { application.terminate() }

        XCTAssertTrue(application.descendants(matching: .any)["Tümü"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["Metin"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["Görseller"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["Parçacıklar"].exists)
    }

    private func launchApplication(language: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchEnvironment["CLIPBOARD_HISTORY_UI_TESTING"] = "1"
        application.launchEnvironment["CLIPBOARD_HISTORY_TEST_ROOT"] = "/private/tmp/ClipboardHistory-UITests-\(UUID().uuidString)"
        application.launchEnvironment["CLIPBOARD_HISTORY_TEST_DEFAULTS"] = "ClipboardHistory.UITests.\(UUID().uuidString)"
        if let language {
            application.launchArguments += [
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "tr" ? "tr_TR" : "en_US"
            ]
        }
        application.launch()
        XCTAssertTrue(application.descendants(matching: .any)["clipboard.panel"].waitForExistence(timeout: 5))
        return application
    }

    private func rows(in application: XCUIApplication) -> XCUIElementQuery {
        application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'")
        )
    }
}
