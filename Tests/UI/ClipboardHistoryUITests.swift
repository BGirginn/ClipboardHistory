import XCTest

@MainActor
final class ClipboardHistoryUITests: XCTestCase {
    func testRightClickReplacesOpenControlCenterPopoverWithNativeMenu() {
        let application = launchApplication()
        defer { terminate(application) }
        let statusItem = application.descendants(matching: .statusItem)["menuBar.controlCenter"]
        let popover = application.descendants(matching: .popover).firstMatch

        XCTAssertTrue(popover.exists)
        statusItem.rightClick()

        XCTAssertTrue(
            application.menuItems["Customize Menu Bar"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(popover.exists)
        application.typeKey(.escape, modifierFlags: [])
    }

    func testOwnStatusItemMovesIntoDrawerAndRestoresToMenuBar() {
        let application = launchApplication()
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.customize"].click()
        let drawerToggle = application.descendants(matching: .any)["customize.notes.drawer"]
        XCTAssertTrue(drawerToggle.waitForExistence(timeout: 2))
        let customizationForm = application.descendants(matching: .any)["customize.form"]
        scrollToControl(drawerToggle, in: customizationForm)
        drawerToggle.click()

        let drawerStatusItem = application.descendants(matching: .statusItem)["menuBar.drawer"]
        XCTAssertTrue(drawerStatusItem.waitForExistence(timeout: 2))
        drawerStatusItem.click()

        XCTAssertTrue(
            application.descendants(matching: .any)["drawer.content"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["drawer.feature.notes"].exists
        )
        application.descendants(matching: .any)["drawer.restore.notes"].click()

        XCTAssertTrue(
            application.descendants(matching: .statusItem)["menuBar.feature.notes"]
                .waitForExistence(timeout: 2)
        )
    }

    func testSearchIsRemovedAndSettingsRemainAccessible() {
        let application = launchApplication()
        defer { terminate(application) }
        openClipboard(in: application)
        XCTAssertFalse(application.textFields.firstMatch.exists)

        application.descendants(matching: .any)["module.settings"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["settings.section.clipboard"]
                .waitForExistence(timeout: 2)
        )
    }

    func testSearchFocusClearAndWindowTransferPreserveQuery() {
        let application = launchApplication()
        defer { terminate(application) }
        openClipboard(in: application)
        application.buttons["clipboard.search"].click()
        let search = application.textFields["clipboard.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        application.typeText("Alpha")
        XCTAssertEqual(search.value as? String, "Alpha")
        XCTAssertEqual(rows(in: application).count, 1)
        application.buttons["module.openWindow"].click()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(application.textFields["clipboard.searchField"].value as? String, "Alpha")
        XCTAssertFalse(application.descendants(matching: .popover).firstMatch.exists)
        application.buttons["clipboard.closeSearch"].click()
        XCTAssertFalse(application.textFields["clipboard.searchField"].exists)
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)
    }

    func testDetailEditorKeepsSpaceAndArrowInputAndSaves() {
        let application = launchApplication()
        defer { terminate(application) }
        openClipboard(in: application)
        rows(in: application).firstMatch.rightClick()
        application.menuItems["Show Details"].click()
        let title = application.textFields["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.click()
        application.typeKey("a", modifierFlags: .command)
        // Bulk typeText drops lowercase i on the Turkish-PC layout in the
        // macOS 27 runner; individual key events preserve the exact input.
        for character in "Edited title" {
            title.typeKey(String(character), modifierFlags: [])
        }
        application.typeKey(.leftArrow, modifierFlags: [])
        application.typeText("!")
        XCTAssertEqual(title.value as? String, "Edited titl!e")
        application.buttons["detail.save"].click()
        application.buttons["detail.back"].click()
        let editedRow = rows(in: application).matching(
            NSPredicate(format: "label CONTAINS %@", "Edited titl!e")
        ).firstMatch
        XCTAssertTrue(editedRow.waitForExistence(timeout: 2))
        editedRow.rightClick()
        application.menuItems["Show Details"].click()
        XCTAssertEqual(title.value as? String, "Edited titl!e")
    }

    func testContextMenuOpensDetailsWithoutClosingPanel() {
        let application = launchApplication()
        defer { terminate(application) }
        openClipboard(in: application)
        let rows = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'clipboard.row.'"))
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        rows.element(boundBy: 0).rightClick()
        application.menuItems["Show Details"].click()
        XCTAssertTrue(application.staticTexts["Item Details"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .popover).firstMatch.exists)
    }

    func testPanelClearAllHistoryConfirmationStaysOpenAndDeletesHistory() {
        let application = launchApplication()
        defer { terminate(application) }
        openClipboard(in: application)
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)

        let cleanup = application.descendants(matching: .any)["header.cleanup"]
        XCTAssertTrue(cleanup.waitForExistence(timeout: 2))
        cleanup.click()
        let clearAll = application.menuItems["Clear All History"]
        XCTAssertTrue(clearAll.waitForExistence(timeout: 2))
        clearAll.click()

        let confirmation = application.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .popover).firstMatch.exists)
        confirmation.buttons["Clear All History"].click()

        XCTAssertTrue(
            application.descendants(matching: .any)["empty.history"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(application.descendants(matching: .popover).firstMatch.exists)
    }

    func testPasteStackCanBeBuiltAndResetFromContextMenu() {
        let application = launchApplication()
        defer { terminate(application) }
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
        defer { terminate(application) }
        openClipboard(in: application)
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)

        application.buttons["Enable Private Mode"].click()
        XCTAssertTrue(application.staticTexts["Private Mode"].waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(rows(in: application).count, 3)
        application.buttons["Disable Private Mode"].click()
        XCTAssertFalse(application.staticTexts["Private Mode"].waitForExistence(timeout: 1))
    }

    func testCommandNumberRestoresVisibleItem() {
        let application = launchApplication()
        defer { terminate(application) }
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
        defer { terminate(application) }
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
        let keyboardControlsBack = application.descendants(matching: .any)["module.back"]
        if keyboardControlsBack.waitForExistence(timeout: 1) {
            XCTAssertTrue(
                application.descendants(matching: .any)["module.settings"].exists
            )
            keyboardControlsBack.click()
        } else {
            XCTAssertTrue(keyboardCleaning.exists)
            keyboardCleaning.click()
        }
        let scrollReverse = application.descendants(matching: .any)["controlCenter.scrollReverse"]
        XCTAssertTrue(scrollReverse.waitForExistence(timeout: 2))
        scrollReverse.click()
        XCTAssertTrue(application.staticTexts["Scroll Reverse"].exists)
    }

    func testAppSettingsSectionsAndMenuBarMetricsAreReachable() {
        let application = launchApplication()
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.settings"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["settings.navigationList"]
                .waitForExistence(timeout: 2)
        )

        selectSettingsButton(
            identifier: "settings.subsection.menuBarMetrics",
            expectedHeading: "Live System Metrics",
            in: application
        )
        let liveMetrics = application.descendants(matching: .any)["customize.metrics.visible"]
        XCTAssertTrue(liveMetrics.waitForExistence(timeout: 2))
        if (liveMetrics.value as? NSNumber)?.boolValue != true {
            liveMetrics.click()
        }
        XCTAssertTrue(
            application.descendants(matching: .any)["customize.metric.cpu"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["customize.metric.memory"]
                .waitForExistence(timeout: 2)
        )
        selectSettingsButton(
            identifier: "settings.subsection.clipboardPrivacy",
            expectedHeading: "Sensitive Content",
            in: application
        )
        selectSettingsButton(
            identifier: "settings.subsection.clipboardStorage",
            expectedHeading: "Retention",
            in: application
        )
        let clearHistory = application.buttons["Clear History"]
        XCTAssertTrue(clearHistory.waitForExistence(timeout: 2))
        application.descendants(matching: .any)["settings.storage"]
            .scroll(byDeltaX: 0, deltaY: 300)
        XCTAssertTrue(clearHistory.isHittable)
        clearHistory.click()
        let confirmClearHistory = application.buttons["Clear All History"]
        XCTAssertTrue(confirmClearHistory.waitForExistence(timeout: 2))
        application.sheets.firstMatch.buttons["Cancel"].click()
        selectSettingsButton(
            identifier: "settings.subsection.clipboardAdvanced",
            expectedHeading: "Duplicate Detection",
            in: application
        )
        selectSettingsButton(
            identifier: "settings.subsection.notesGeneral",
            expectedHeading: "Stored Notes",
            in: application
        )
        selectSettingsButton(
            identifier: "settings.subsection.inputKeyboardCleaning",
            expectedHeading: "settings.inputTools",
            in: application
        )
    }

    func testNotesAndInputToolsSettingsButtonsOpenRelevantSections() {
        let application = launchApplication()
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.notes"].click()
        let settingsButton = application.descendants(matching: .any)["module.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.click()
        XCTAssertTrue(
            application.descendants(matching: .any)["Stored Notes"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["settings.section.notes"].isHittable
        )

        application.descendants(matching: .any)["settings.close"].click()
        application.descendants(matching: .any)["module.back"].click()
        let scrollReverse = application.descendants(matching: .any)["controlCenter.scrollReverse"]
        XCTAssertTrue(scrollReverse.waitForExistence(timeout: 2))
        scrollReverse.click()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.click()
        XCTAssertTrue(
            application.descendants(matching: .any)["settings.inputTools"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["settings.section.inputTools"].isHittable
        )
    }

    func testDynamicCollectionAndLazyMenusAreReachable() {
        let application = launchApplication()
        defer { terminate(application) }

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
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.notes"].click()
        application.descendants(matching: .any)["notes.new"].click()
        let body = application.descendants(matching: .any)["notes.editor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        body.click()
        body.typeText("First note body")
        body.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(application.staticTexts["Saved"].waitForExistence(timeout: 2))
        application.buttons["Back to Notes"].click()

        let rows = application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'notes.row.'")
        )
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.click()
        XCTAssertTrue(body.waitForExistence(timeout: 2))
        body.click()
        body.typeKey("a", modifierFlags: .command)
        body.typeText("Updated note body")
        body.typeKey("s", modifierFlags: .command)
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
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.customize"].click()
        XCTAssertTrue(application.staticTexts["Customize Menu Bar"].waitForExistence(timeout: 2))

        let clipboardStandalone = application.descendants(matching: .any)[
            "customize.clipboard.standalone"
        ]
        XCTAssertTrue(clipboardStandalone.waitForExistence(timeout: 2))
        let customizationForm = application.descendants(matching: .any)["customize.form"]
        XCTAssertTrue(customizationForm.waitForExistence(timeout: 2))
        scrollToControl(clipboardStandalone, in: customizationForm)
        clipboardStandalone.click()
        let alwaysVisible = application.menuItems["Always"]
        XCTAssertTrue(alwaysVisible.waitForExistence(timeout: 2))
        alwaysVisible.click()
        XCTAssertEqual(clipboardStandalone.value as? String, "Always")

        let clipboardAction = application.descendants(matching: .any)["customize.clipboard.action"]
        XCTAssertTrue(clipboardAction.waitForExistence(timeout: 2))
        scrollToControl(clipboardAction, in: customizationForm)
        clipboardAction.click()
        XCTAssertTrue(
            application.menuItems["Pause or Resume Recording"].waitForExistence(timeout: 2)
        )
        application.menuItems["Pause or Resume Recording"].click()
        XCTAssertEqual(clipboardAction.value as? String, "Pause or Resume Recording")

        let centerItem = application.descendants(matching: .any)["customize.controlCenterItem"]
        XCTAssertTrue(centerItem.waitForExistence(timeout: 2))
        scrollToControl(centerItem, in: customizationForm, deltaY: 160)
        centerItem.click()
        let controlCenterStatus = application.descendants(matching: .statusItem)["menuBar.controlCenter"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: controlCenterStatus)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(
            application.descendants(matching: .statusItem)["menuBar.feature.clipboard"]
                .waitForExistence(timeout: 2)
        )
    }

    func testSystemMonitorAndExperimentalAudioMixerOpenFromControlCenter() {
        let application = launchApplication()
        defer { terminate(application) }

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

    func testSystemMonitorChartsAndDetailsAreReachable() {
        let application = launchApplication()
        defer { terminate(application) }

        application.descendants(matching: .any)["controlCenter.systemMonitor"].click()
        let details = application.buttons["systemMonitor.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 2))
        details.click()
        XCTAssertEqual(details.value as? String, "Expanded")

        let scrollView = application.scrollViews.firstMatch
        scrollView.scroll(byDeltaX: 0, deltaY: 400)
        XCTAssertTrue(
            application.descendants(matching: .any)["systemMonitor.disk"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["Memory Breakdown"].exists
        )
    }

    private func scrollToControl(
        _ control: XCUIElement,
        in container: XCUIElement,
        deltaY: CGFloat = -160
    ) {
        // Wheel direction varies with the host's scrolling preferences. Search
        // both directions without changing global mouse/trackpad settings.
        for direction in [deltaY, -deltaY] {
            for _ in 0..<12 {
                if control.isHittable && container.frame.insetBy(dx: 0, dy: 4).contains(control.frame) {
                    return
                }
                container.scroll(byDeltaX: 0, deltaY: direction)
            }
        }
        XCTFail("Control is not fully visible: \(control.identifier), frame=\(control.frame), container=\(container.frame)")
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
        let statusItem = application.descendants(matching: .statusItem)["menuBar.controlCenter"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        let statusItemFrame = statusItem.frame

        let controlCenter = application.descendants(matching: .any)["controlCenter.clipboard"]
        if !controlCenter.waitForExistence(timeout: 2) {
            statusItem.click()
        }
        if !controlCenter.waitForExistence(timeout: 2) {
            // macOS can discard the first synthetic status-item click while a
            // previous UI-test application is finishing its menu-bar teardown.
            statusItem.click()
        }
        XCTAssertTrue(controlCenter.waitForExistence(timeout: 5))
        let popover = application.descendants(matching: .popover).firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 2))
        XCTAssertEqual(popover.frame.midX, statusItemFrame.midX, accuracy: 2)
        XCTAssertEqual(popover.frame.minY, statusItemFrame.maxY, accuracy: 2)
        return application
    }

    private func terminate(_ application: XCUIApplication) {
        application.terminate()
        XCTAssertTrue(
            application.wait(for: .notRunning, timeout: 5),
            "UI-test application did not finish its asynchronous shutdown"
        )
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

    private func selectSettingsButton(
        identifier: String,
        expectedHeading: String,
        in application: XCUIApplication
    ) {
        let allSettings = application.descendants(matching: .any)["settings.all"]
        if allSettings.exists && allSettings.isHittable {
            allSettings.click()
        }
        let navigation = application.descendants(matching: .any)["settings.navigationList"]
        XCTAssertTrue(
            navigation.waitForExistence(timeout: 2),
            "Missing settings navigation list"
        )
        let button = application.descendants(matching: .any)[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Missing settings button: \(identifier)")
        scrollToControl(button, in: navigation)
        button.click()
        XCTAssertTrue(
            application.descendants(matching: .any)[expectedHeading]
                .waitForExistence(timeout: 2),
            "Settings section did not open: \(identifier)"
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

}
