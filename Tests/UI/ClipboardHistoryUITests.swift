import XCTest

@MainActor
final class ClipboardHistoryUITests: XCTestCase {
    func testSearchIsRemovedAndSettingsRemainAccessible() {
        let application = launchApplication()
        defer { application.terminate() }
        openClipboard(in: application)
        XCTAssertFalse(application.textFields.firstMatch.exists)

        application.descendants(matching: .any)["module.settings"].click()
        XCTAssertTrue(application.staticTexts["Settings"].waitForExistence(timeout: 2))
    }

    func testContextMenuOpensDetailsWithoutClosingPanel() {
        let application = launchApplication()
        defer { application.terminate() }
        openClipboard(in: application)
        let rows = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'"))
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        rows.element(boundBy: 0).rightClick()
        application.menuItems["Show Details"].click()
        XCTAssertTrue(application.staticTexts["Item Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .popover).firstMatch.exists)
    }

    func testPasteStackCanBeBuiltAndResetFromContextMenu() {
        let application = launchApplication()
        defer { application.terminate() }
        openClipboard(in: application)
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
        openClipboard(in: application)
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)

        openHeaderActions(in: application)
        application.menuItems["Enable Private Mode"].click()
        XCTAssertTrue(application.staticTexts["Private Mode"].waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)
        openHeaderActions(in: application)
        application.menuItems["Disable Private Mode"].click()
        XCTAssertFalse(application.staticTexts["Private Mode"].waitForExistence(timeout: 1))
    }

    func testCommandNumberRestoresVisibleItem() {
        let application = launchApplication()
        defer { application.terminate() }
        openClipboard(in: application)
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
        openClipboard(in: application)

        let filter = application.descendants(matching: .any)["Filtre"]
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        filter.click()
        XCTAssertTrue(application.menuItems["Tümü"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.menuItems["Metin"].exists)
        XCTAssertTrue(application.menuItems["Görseller"].exists)
        XCTAssertTrue(application.menuItems["Parçacıklar"].exists)
        application.typeKey(.escape, modifierFlags: [])

        let panel = application.descendants(matching: .popover).firstMatch
        let sort = application.descendants(matching: .any)["Sırala"]
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(sort.waitForExistence(timeout: 2))
        XCTAssertTrue(sort.isHittable)
        XCTAssertLessThanOrEqual(sort.frame.maxX, panel.frame.maxX + 1)

        application.descendants(matching: .any)["module.back"].click()
        let keyboardCleaning = application.descendants(matching: .any)["controlCenter.keyboardCleaning"]
        XCTAssertTrue(keyboardCleaning.waitForExistence(timeout: 2))
        keyboardCleaning.click()
        XCTAssertTrue(application.staticTexts["Klavye Temizlik Modu"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.buttons["Klavye Temizliğini Başlat"].exists)
        application.descendants(matching: .any)["module.back"].click()
        application.descendants(matching: .any)["controlCenter.scrollReverse"].click()
        XCTAssertTrue(application.staticTexts["Scroll Reverse"].exists)
    }

    func testSettingsSectionsDynamicCollectionAndLazyMenusAreReachable() {
        let application = launchApplication()
        defer { application.terminate() }

        application.descendants(matching: .any)["controlCenter.settings"].click()
        XCTAssertTrue(application.staticTexts["Behavior"].waitForExistence(timeout: 2))

        selectSettingsSection("Privacy", expectedHeading: "Sensitive Content", in: application)
        let privateMode = application.descendants(matching: .any)["settings.privateMode"]
        XCTAssertTrue(privateMode.waitForExistence(timeout: 2))
        privateMode.click()

        selectSettingsSection("Security", expectedHeading: "Application Lock", in: application)
        selectSettingsSection("Storage", expectedHeading: "Retention", in: application)
        selectSettingsSection("Advanced", expectedHeading: "Duplicate Detection", in: application)

        XCTAssertTrue(application.buttons["Delete Coverage Collection"].waitForExistence(timeout: 2))

        application.descendants(matching: .any)["settings.back"].click()
        openClipboard(in: application)

        openSubmenu("Copy As", expectedItem: "Original", in: application)
        openSubmenu("Paste As", expectedItem: "Plain Text", in: application)
        openSubmenu("Move to Collection", expectedItem: "Coverage Collection", in: application)

        let sort = application.descendants(matching: .any)["Sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 2))
        sort.click()
        XCTAssertTrue(application.menuItems["Newest First"].waitForExistence(timeout: 2))
        application.typeKey(.escape, modifierFlags: [])

        let firstRow = rows(in: application).element(boundBy: 0)
        firstRow.rightClick()
        application.menuItems["Show Details"].click()
        let transform = application.descendants(matching: .any)["detail.transform"]
        XCTAssertTrue(transform.waitForExistence(timeout: 2))
        transform.click()
        XCTAssertTrue(application.menuItems["Uppercase"].waitForExistence(timeout: 2))
        application.menuItems["Uppercase"].click()
    }

    func testNoteCanBeCreatedReopenedEditedAndDeleted() {
        let application = launchApplication()
        defer { application.terminate() }

        application.descendants(matching: .any)["controlCenter.notes"].click()
        application.descendants(matching: .any)["notes.new"].click()
        let body = application.descendants(matching: .any)["notes.editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        application.typeText("First note body")
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(application.staticTexts["Saved"].waitForExistence(timeout: 2))
        application.buttons["Back to Notes"].click()

        let rows = application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'notes.row.'")
        )
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.click()
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        body.click()
        application.typeKey("a", modifierFlags: .command)
        application.typeText("Updated note body")
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(application.staticTexts["Saved"].waitForExistence(timeout: 2))
        application.buttons["Back to Notes"].click()
        let updatedRow = NSPredicate(format: "label CONTAINS[c] 'Updated note body'")
        expectation(for: updatedRow, evaluatedWith: rows.firstMatch)
        waitForExpectations(timeout: 2)

        rows.firstMatch.click()
        let deleteButton = application.descendants(matching: .any)["notes.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: deleteButton
        )
        waitForExpectations(timeout: 2)
        deleteButton.click()
        let confirmDelete = application.descendants(matching: .any)["notes.delete.confirm"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 2))
        confirmDelete.click()
        XCTAssertTrue(application.staticTexts["No Notes Yet"].waitForExistence(timeout: 2))
    }

    func testMenuBarCustomizationSupportsIndependentModulePlacement() {
        let application = launchApplication()
        defer { application.terminate() }

        application.descendants(matching: .any)["controlCenter.customize"].click()
        XCTAssertTrue(application.staticTexts["Customize Menu Bar"].waitForExistence(timeout: 2))

        let clipboardStandalone = application.descendants(matching: .any)[
            "customize.clipboard.standalone"
        ]
        XCTAssertTrue(clipboardStandalone.waitForExistence(timeout: 2))
        clipboardStandalone.click()

        let clipboardAction = application.descendants(matching: .any)["customize.clipboard.action"]
        XCTAssertTrue(clipboardAction.waitForExistence(timeout: 2))
        clipboardAction.click()
        XCTAssertTrue(
            application.menuItems["Pause or Resume Recording"].waitForExistence(timeout: 2)
        )
        application.menuItems["Pause or Resume Recording"].click()

        let centerItem = application.descendants(matching: .any)["customize.controlCenterItem"]
        XCTAssertTrue(centerItem.waitForExistence(timeout: 2))
        centerItem.click()
        XCTAssertFalse(centerItem.isSelected)

        clipboardStandalone.click()
        let acknowledge = application.sheets.buttons["OK"].firstMatch
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 2))
        acknowledge.click()
    }

    func testSystemMonitorAndExperimentalAudioMixerOpenFromControlCenter() {
        let application = launchApplication()
        defer { application.terminate() }

        let systemMonitor = application.descendants(matching: .any)["controlCenter.systemMonitor"]
        XCTAssertTrue(systemMonitor.waitForExistence(timeout: 2))
        systemMonitor.click()
        XCTAssertTrue(application.staticTexts["System Monitor"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["systemMonitor.cpu"].exists)
        XCTAssertTrue(application.buttons["Refresh"].exists)

        application.descendants(matching: .any)["module.back"].click()
        let audioMixer = application.descendants(matching: .any)["controlCenter.audioMixer"]
        XCTAssertTrue(audioMixer.waitForExistence(timeout: 2))
        audioMixer.click()
        XCTAssertTrue(application.staticTexts["Audio Mixer"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.staticTexts["Applications"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["Audio Actions"].exists)
    }

    private func launchApplication(language: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        let testRoot = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistory-UITests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let defaultsSuite = "ClipboardHistory.UITests.\(UUID().uuidString)"
        do {
            try FileManager.default.createDirectory(
                at: testRoot,
                withIntermediateDirectories: false
            )
        } catch {
            XCTFail("Could not create isolated UI-test storage: \(error)")
        }
        addTeardownBlock {
            do {
                try FileManager.default.removeItem(at: testRoot)
            } catch {
                XCTFail("Could not remove isolated UI-test storage: \(error)")
            }
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(
                forName: defaultsSuite
            )
        }
        application.launchEnvironment["CLIPBOARD_HISTORY_UI_TESTING"] = "1"
        application.launchEnvironment["CLIPBOARD_HISTORY_TEST_ROOT"] = testRoot.path
        application.launchEnvironment["CLIPBOARD_HISTORY_TEST_DEFAULTS"] = defaultsSuite
        if let language {
            application.launchArguments += [
                "-AppleLanguages", "(\(language))",
                "-AppleLocale", language == "tr" ? "tr_TR" : "en_US"
            ]
        }
        application.launch()
        XCTAssertTrue(application.descendants(matching: .any)["controlCenter.clipboard"].waitForExistence(timeout: 5))
        return application
    }

    private func openClipboard(in application: XCUIApplication) {
        let clipboard = application.descendants(matching: .any)["controlCenter.clipboard"]
        XCTAssertTrue(clipboard.waitForExistence(timeout: 2))
        clipboard.click()
        XCTAssertTrue(
            application.descendants(matching: .any)["module.back"].waitForExistence(timeout: 2)
        )
    }

    private func rows(in application: XCUIApplication) -> XCUIElementQuery {
        application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'")
        )
    }

    private func selectSettingsSection(
        _ title: String,
        expectedHeading: String,
        in application: XCUIApplication
    ) {
        let section = application.descendants(matching: .any)[title]
        XCTAssertTrue(section.waitForExistence(timeout: 2), "Missing settings section: \(title)")
        section.click()
        XCTAssertTrue(
            application.staticTexts[expectedHeading].waitForExistence(timeout: 2),
            "Settings section did not open: \(title)"
        )
    }

    private func openSubmenu(
        _ title: String,
        expectedItem: String,
        in application: XCUIApplication
    ) {
        rows(in: application).element(boundBy: 0).rightClick()
        let submenu = application.menuItems[title]
        XCTAssertTrue(submenu.waitForExistence(timeout: 2), "Missing submenu: \(title)")
        submenu.hover()
        XCTAssertTrue(
            application.menuItems[expectedItem].waitForExistence(timeout: 2),
            "Missing submenu item: \(expectedItem)"
        )
        application.typeKey(.escape, modifierFlags: [])
    }

    private func openHeaderActions(in application: XCUIApplication) {
        let actions = application.descendants(matching: .any)["More"]
        XCTAssertTrue(actions.waitForExistence(timeout: 2))
        XCTAssertTrue(actions.isHittable)
        actions.click()
    }
}
