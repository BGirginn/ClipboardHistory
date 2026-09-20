import AppKit
import Carbon
import CoreAudio
import XCTest

@testable import ClipboardHistoryTestHost

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testLiveDependenciesCreateConfiguredAppKitObjects() async {
        let context = makeContext()
        let dependencies = MenuBarControllerDependencies.live
        let statusItem = dependencies.makeStatusItem()
        let popover = dependencies.makePopover()
        let panel = dependencies.makePanel(context.appModel)

        XCTAssertNotNil(statusItem.button)
        XCTAssertEqual(panel.title, "CoreDeck")
        XCTAssertEqual(panel.contentMinSize, NSSize(width: 340, height: 420))
        XCTAssertNotNil(panel.contentViewController)
        dependencies.quickLookPresenter.close()

        popover.close()
        panel.close()
        NSStatusBar.system.removeStatusItem(statusItem)
        await cleanup(context)
    }

    func testControllerCallbacksModesCloseAndStopWithoutAnimatingAppKitWindows() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        let popover = NSPopover()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let quickLook = MenuQuickLookSpy()
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: { NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) },
            makePopover: { popover },
            makePanel: { _ in panel },
            quickLookPresenter: quickLook
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )
        let statusItem = try XCTUnwrap(controller.statusItems[.controlCenter])
        XCTAssertTrue(popover.animates)
        XCTAssertNotNil(popover.contentViewController)
        panel.animationBehavior = .none

        context.settings.appearance = .light
        XCTAssertEqual(popover.appearance?.name, .aqua)
        context.settings.appearance = .dark
        XCTAssertEqual(popover.appearance?.name, .darkAqua)
        context.settings.appearance = .system
        XCTAssertNil(popover.appearance)

        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertNil(controller.shortcutRegistrationError)
        controller.popoverWillShow(Notification(name: NSPopover.willShowNotification))
        context.viewModel.menuCommandDidRun?()
        let preview = ClipboardItem(type: .text, text: "preview", hash: "preview")
        context.viewModel.requestPreview?(preview)
        XCTAssertEqual(quickLook.shownItems, [preview])
        context.viewModel.setPrivateModeEnabled(true)
        XCTAssertTrue(statusItem.button?.toolTip?.contains("Private Mode") == true)
        context.viewModel.setPrivateModeEnabled(false)
        context.viewModel.pauseUntil = .now.addingTimeInterval(60)
        context.viewModel.privateModeDidChange?(false)
        XCTAssertTrue(statusItem.button?.toolTip?.contains("paused") == true)
        context.viewModel.pauseUntil = nil
        context.viewModel.isPrivateMode = false
        context.viewModel.privateModeDidChange?(false)
        XCTAssertEqual(
            statusItem.button?.toolTip,
            "CoreDeck — right-click for options"
        )
        controller.closePopover()
        XCTAssertFalse(controller.isPopoverShown)
        XCTAssertGreaterThanOrEqual(quickLook.closeCount, 1)

        context.settings.panelPresentationMode = .detachable
        for edge in PanelScreenEdge.allCases {
            context.settings.panelScreenEdge = edge
        }

        controller.stop()
        XCTAssertGreaterThanOrEqual(quickLook.closeCount, 2)
        await cleanup(context)
    }

    func testOpenInWindowReusesWindowAndPreservesSearchSelectionAndDraft() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        var createdWindows = 0
        let presenter = ApplicationWindowController(
            appModel: context.appModel,
            makeWindow: { createdWindows += 1; return MenuPanelStub() },
            makeContentViewController: { _ in NSViewController() }
        )
        let popover = MenuPopoverStub()
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: { NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) },
                makePopover: { popover }, makePanel: { _ in MenuPanelStub() }, quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub(), applicationWindowPresenter: presenter
        )
        await context.viewModel.insert(.text(value: "Synthetic", hash: "transfer"))
        let item = try XCTUnwrap(context.viewModel.items.first)
        context.appModel.showClipboard()
        context.viewModel.toggleSearch()
        context.viewModel.searchText = "Synthetic"
        context.viewModel.selectOnly(item)
        controller.showActiveFeature()
        context.appModel.requestOpenWindow?()
        XCTAssertFalse(popover.isShown)
        XCTAssertEqual(context.appModel.router.activeFeature, .clipboard)
        XCTAssertEqual(context.viewModel.searchText, "Synthetic")
        XCTAssertEqual(context.viewModel.selectedItemID, item.id)
        context.appModel.showQuickNote()
        context.appModel.notes.draftBody = "Preserved draft"
        let session = context.appModel.notes.draftSessionID
        for _ in 0..<100 { context.appModel.requestOpenWindow?() }
        XCTAssertEqual(createdWindows, 1)
        XCTAssertEqual(context.appModel.notes.draftSessionID, session)
        XCTAssertEqual(context.appModel.notes.draftBody, "Preserved draft")
        presenter.stop()
        controller.stop()
        await cleanup(context)
    }

    func testControllerUsesApplicationWindowWhenNoStatusItemAnchorExists() async {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setControlCenterItemVisible(false)
        context.appModel.controlCenter.setDrawerItemVisible(false)
        let windowPresenter = MenuApplicationWindowPresenterSpy()
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    XCTFail("A status item should not be created for a window-only configuration")
                    return NSStatusItem()
                },
                makePopover: NSPopover.init,
                makePanel: { _ in NSPanel() },
                quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub(),
            applicationWindowPresenter: windowPresenter
        )

        context.appModel.showClipboard()
        controller.showControlCenter()

        XCTAssertEqual(context.appModel.router.activeFeature, .controlCenter)
        XCTAssertEqual(windowPresenter.showActiveFeatureCount, 1)
        XCTAssertTrue(windowPresenter.isWindowVisible)

        controller.stop()
        await cleanup(context)
    }

    func testDrawerOwnsMovedFeatureAndExcludesQuickCenterPresentation() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .notes)
        let popover = MenuPopoverStub()
        let drawerPopover = MenuPopoverStub()
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: { popover },
                makeDrawerPopover: { drawerPopover },
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy(),
                currentEvent: { nil }
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        XCTAssertNotNil(controller.statusItems[.drawer])
        XCTAssertNotNil(controller.statusItems[.feature(.notes)])
        let drawerContent = try XCTUnwrap(drawerPopover.contentViewController)
        context.settings.appearance = .dark
        XCTAssertEqual(drawerPopover.appearance?.name, .darkAqua)

        context.appModel.controlCenter.setShownInDrawer(true, for: .notes)

        XCTAssertNil(controller.statusItems[.feature(.notes)])
        try XCTUnwrap(controller.statusItems[.drawer]?.button).performClick(nil)
        await settleMenuAction()
        XCTAssertTrue(drawerPopover.isShown)
        XCTAssertFalse(popover.isShown)
        XCTAssertTrue(drawerPopover.contentViewController === drawerContent)

        try XCTUnwrap(controller.statusItems[.controlCenter]?.button).performClick(nil)
        await settleMenuAction()
        XCTAssertFalse(drawerPopover.isShown)
        XCTAssertTrue(popover.isShown)

        context.appModel.controlCenter.setShownInDrawer(false, for: .notes)
        XCTAssertNotNil(controller.statusItems[.feature(.notes)])

        context.appModel.controlCenter.setMetricGroupVisible(true)
        context.appModel.controlCenter.setMetricsAsSeparateItems(false)
        XCTAssertNotNil(controller.statusItems[.metricGroup])
        context.appModel.controlCenter.setShownInDrawer(true, for: .systemMonitor)
        XCTAssertNil(controller.statusItems[.metricGroup])
        context.appModel.controlCenter.restoreFeatureToMenuBar(.systemMonitor)
        XCTAssertNotNil(controller.statusItems[.metricGroup])

        for _ in 0..<100 {
            controller.toggleDrawer()
            await settleMenuAction()
            XCTAssertTrue(drawerPopover.isShown)
            XCTAssertTrue(drawerPopover.contentViewController === drawerContent)
            controller.toggleDrawer()
            XCTAssertFalse(drawerPopover.isShown)
        }
        context.appModel.controlCenter.setDrawerItemVisible(false)
        XCTAssertNil(controller.statusItems[.drawer])

        controller.stop()
        await cleanup(context)
    }

    func testPopoverDetachableStatusActionShortcutAndPublisherCallbacks() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        await context.viewModel.insert(.text(value: "shortcut", hash: "shortcut"))
        let popover = MenuPopoverStub()
        let panel = MenuPanelStub()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        let eventMonitor = MenuRecordingPanelEventMonitor()
        let shortcutBackend = MenuShortcutBackendStub()
        var statusItemEvent: NSEvent?
        var presentedStatusMenu: NSMenu?
        var terminationCount = 0
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: { NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) },
            makePopover: { popover },
            makePanel: { _ in panel },
            quickLookPresenter: MenuQuickLookSpy(),
            currentEvent: { statusItemEvent },
            presentStatusMenu: { menu, _ in presentedStatusMenu = menu },
            terminateApplication: { terminationCount += 1 }
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: eventMonitor,
            shortcutBackend: shortcutBackend,
            popoverAnchor: { anchor }
        )

        let statusItem = try XCTUnwrap(controller.statusItems[.controlCenter])
        context.settings.globalShortcutPresetID = GlobalShortcut.presets[1].id
        context.settings.globalShortcutEnabled = true
        XCTAssertGreaterThanOrEqual(shortcutBackend.installCount, 1)
        XCTAssertGreaterThanOrEqual(shortcutBackend.registerCount, 1)

        context.settings.shortcutActivationMode = .toggle
        context.appModel.router.openSettings()
        context.viewModel.detailItem = context.viewModel.items.first
        context.viewModel.searchText = "stale presentation"
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertTrue(popover.isShown, "Global shortcut should show the clipboard popover")
        XCTAssertEqual(context.appModel.router.activeFeature, .clipboard)
        XCTAssertNil(context.viewModel.detailItem)
        XCTAssertEqual(context.viewModel.searchText, "")
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        XCTAssertFalse(popover.isShown)

        context.settings.shortcutActivationMode = .hold
        shortcutBackend.fire(UInt32(kEventHotKeyPressed))
        shortcutBackend.fire(UInt32(kEventHotKeyReleased))
        controller.closePopover()

        let centerPresented = expectation(description: "Control Center presentation")
        popover.didShow = { centerPresented.fulfill() }
        statusItem.button?.performClick(nil)
        await fulfillment(of: [centerPresented], timeout: 2)
        popover.didShow = nil
        XCTAssertTrue(popover.isShown, "Control Center status item should show the popover")
        XCTAssertTrue(popover.positioningView === anchor)
        XCTAssertEqual(popover.recordedPositioningRect, anchor.bounds)
        XCTAssertEqual(popover.recordedPreferredEdge, .minY)
        statusItemEvent = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        statusItem.button?.performClick(nil)
        XCTAssertFalse(popover.isShown, "Right-click menu should replace the open popover")
        XCTAssertEqual(
            presentedStatusMenu?.items.map(\.title),
            [
                "Customize Menu Bar",
                "Open Settings",
                "",
                "Quit CoreDeck"
            ]
        )
        XCTAssertTrue(presentedStatusMenu?.items.compactMap(\.image).isEmpty == false)
        XCTAssertEqual(terminationCount, 0)
        if let quitIndex = presentedStatusMenu?.items.indices.last {
            presentedStatusMenu?.performActionForItem(at: quitIndex)
        }
        XCTAssertEqual(terminationCount, 1)
        statusItemEvent = nil
        let event = try XCTUnwrap(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            )
        )
        _ = eventMonitor.fireLocal(event)
        _ = controller.isStatusItemEvent(event)
        controller.closePopover()

        context.settings.panelPresentationMode = .detachable
        controller.showPopover()
        XCTAssertTrue(panel.isVisible, "Detachable presentation should show its panel")
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 1)
        for edge in PanelScreenEdge.allCases {
            context.settings.panelScreenEdge = edge
            controller.positionDetachablePanel()
        }
        controller.togglePopover()
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 0)

        controller.showPopover()
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: panel))
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 0)

        controller.stop()
        await cleanup(context)
    }

    func testConfigurationAddsAndRemovesStandaloneStatusItemsWithoutRestart() async {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setDrawerItemVisible(false)
        var createdItems: [NSStatusItem] = []
        var removedItems: [NSStatusItem] = []
        var currentEvent: NSEvent?
        var presentedMenu: NSMenu?
        let popover = MenuPopoverStub()
        let windowPresenter = MenuApplicationWindowPresenterSpy()
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                createdItems.append(item)
                return item
            },
            removeStatusItem: { item in
                removedItems.append(item)
                NSStatusBar.system.removeStatusItem(item)
            },
            makePopover: { popover },
            makePanel: { _ in MenuPanelStub() },
            quickLookPresenter: MenuQuickLookSpy(),
            currentEvent: { currentEvent },
            presentStatusMenu: { menu, _ in presentedMenu = menu }
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub(),
            applicationWindowPresenter: windowPresenter
        )

        XCTAssertEqual(createdItems.count, 1)
        XCTAssertEqual(createdItems.first?.autosaveName, "ClipboardHistory.ControlCenter")
        XCTAssertEqual(
            createdItems.first?.button?.accessibilityIdentifier(),
            "menuBar.controlCenter"
        )

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .notes)
        XCTAssertEqual(createdItems.count, 2)
        XCTAssertEqual(createdItems.last?.autosaveName, "ClipboardHistory.Feature.notes")
        XCTAssertEqual(
            createdItems.last?.button?.accessibilityIdentifier(),
            "menuBar.feature.notes"
        )

        controller.showControlCenter()
        XCTAssertTrue(popover.isShown)
        popover.presentationFailuresRemaining = 2
        context.appModel.controlCenter.setControlCenterItemVisible(false)
        for _ in 0..<20 where !popover.isShown {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(controller.activeAnchorID, .feature(.notes))
        XCTAssertTrue(popover.positioningView === controller.statusItems[.feature(.notes)]?.button)
        XCTAssertEqual(popover.showCallCount, 4)
        XCTAssertEqual(removedItems.count, 1)

        currentEvent = NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        createdItems.last?.button?.performClick(nil)
        XCTAssertEqual(
            presentedMenu?.items.map(\.title),
            [
                "Open Notes",
                "New Note",
                "",
                "Customize Menu Bar",
                "Open Settings",
                "",
                "Quit CoreDeck"
            ]
        )

        context.appModel.controlCenter.setStandaloneItemVisible(false, for: .notes)
        await settleMenuAction()
        XCTAssertEqual(removedItems.count, 2)
        XCTAssertEqual(createdItems.count, 2)
        XCTAssertEqual(controller.activeAnchorID, .controlCenter)
        XCTAssertFalse(popover.isShown)
        XCTAssertEqual(windowPresenter.showActiveFeatureCount, 0)
        XCTAssertFalse(windowPresenter.isWindowVisible)

        controller.stop()
        XCTAssertEqual(removedItems.count, 2)
        await cleanup(context)
    }

    func testFeatureAndMetricMenusRouteEverySharedAction() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        var createdItems: [NSStatusItem] = []
        var currentEvent: NSEvent?
        var presentedMenu: NSMenu?
        var terminationCount = 0
        let popover = MenuPopoverStub()
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                createdItems.append(item)
                return item
            },
            removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
            makePopover: { popover },
            makePanel: { _ in MenuPanelStub() },
            quickLookPresenter: MenuQuickLookSpy(),
            currentEvent: { currentEvent },
            presentStatusMenu: { menu, _ in presentedMenu = menu },
            terminateApplication: { terminationCount += 1 }
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .systemMonitor)
        let systemItem = try XCTUnwrap(
            createdItems.first { $0.autosaveName == "ClipboardHistory.Metric.cpu" }
        )
        XCTAssertNil(controller.statusItems[.feature(.systemMonitor)])
        XCTAssertTrue(
            controller.renderedStatusStates[.metric(.cpu)]?.title.contains("CPU") == true
        )
        XCTAssertEqual(controller.metricStripViews[.metric(.cpu)]?.segments.count, 1)
        XCTAssertGreaterThan(systemItem.length, NSStatusItem.squareLength)
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 1)
        currentEvent = rightMouseEvent()
        systemItem.button?.performClick(nil)
        XCTAssertEqual(controller.activeAnchorID, .metric(.cpu))
        let metricMenu = try XCTUnwrap(presentedMenu)

        performMenuAction(metricMenu.items[0])
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.activeFeature, .systemMonitor)
        performMenuAction(metricMenu.items[1])
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.activeFeature, .menuBarCustomization)
        performMenuAction(metricMenu.items[2])
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.activeFeature, .settings)
        XCTAssertEqual(context.appModel.router.settingsSection, .systemMonitor)
        performMenuAction(metricMenu.items[4])
        XCTAssertEqual(terminationCount, 1)

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .notes)
        let notesItem = try XCTUnwrap(
            createdItems.first { $0.autosaveName == "ClipboardHistory.Feature.notes" }
        )
        notesItem.button?.performClick(nil)
        performMenuAction(try XCTUnwrap(presentedMenu).items[4])
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.settingsSection, .notes)

        for (id, expectedSection) in [
            (UtilityFeatureID.clipboard, AppSettingsSection.clipboard),
            (.scrollReverse, .inputTools),
            (.audioMixer, .audioMixer)
        ] {
            context.appModel.controlCenter.setStandaloneItemVisible(true, for: id)
            let featureItem = try XCTUnwrap(
                createdItems.first {
                    $0.autosaveName == "ClipboardHistory.Feature.\(id.rawValue)"
                }
            )
            featureItem.button?.performClick(nil)
            let featureMenu = try XCTUnwrap(presentedMenu)
            XCTAssertEqual(featureMenu.items.count, 7)

            performMenuAction(featureMenu.items[0])
            await settleMenuAction()
            XCTAssertEqual(context.appModel.router.activeFeature, context.appModel.route(for: id))

            performMenuAction(featureMenu.items[1])
            await settleMenuAction()
            performMenuAction(featureMenu.items[3])
            await settleMenuAction()
            XCTAssertEqual(context.appModel.router.activeFeature, .menuBarCustomization)

            performMenuAction(featureMenu.items[4])
            await settleMenuAction()
            XCTAssertEqual(context.appModel.router.settingsSection, expectedSection)
        }

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .keyboardCleaning)
        let inputToolsItem = try XCTUnwrap(
            createdItems.first {
                $0.autosaveName == "ClipboardHistory.Feature.keyboardCleaning"
            }
        )
        inputToolsItem.button?.performClick(nil)
        performMenuAction(try XCTUnwrap(presentedMenu).items[4])
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.settingsSection, .inputTools)

        currentEvent = nil
        systemItem.button?.performClick(nil)
        await settleMenuAction()
        XCTAssertEqual(context.appModel.router.activeFeature, .systemMonitor)
        systemItem.button?.performClick(nil)
        await settleMenuAction()
        XCTAssertFalse(popover.isShown)

        controller.stop()
        await cleanup(context)
    }

    func testMetricStatusItemsUseSingleLineStableWidthWhileFeatureItemsStaySquare() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        let dependencies = MenuBarControllerDependencies(
            makeStatusItem: {
                NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            },
            removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
            makePopover: MenuPopoverStub.init,
            makePanel: { _ in MenuPanelStub() },
            quickLookPresenter: MenuQuickLookSpy()
        )
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: dependencies,
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        context.appModel.controlCenter.setStandaloneItemVisible(true, for: .notes)
        context.appModel.controlCenter.setMetricVisible(true, metric: .networkDownload)
        context.appModel.controlCenter.setMetricsAsSeparateItems(false)
        context.appModel.controlCenter.setMetricGroupVisible(true)
        try await Task.sleep(for: .milliseconds(200))

        let notesItem = try XCTUnwrap(controller.statusItems[.feature(.notes)])
        let metricItem = try XCTUnwrap(controller.statusItems[.metricGroup])
        let metricButton = try XCTUnwrap(metricItem.button)
        let metricStrip = try XCTUnwrap(controller.metricStripViews[.metricGroup])

        XCTAssertEqual(notesItem.length, NSStatusItem.squareLength)
        XCTAssertEqual(notesItem.button?.title, "")
        XCTAssertNotNil(notesItem.button?.image)
        XCTAssertNotEqual(metricItem.length, NSStatusItem.variableLength)
        XCTAssertGreaterThan(metricItem.length, NSStatusItem.squareLength)
        XCTAssertEqual(metricButton.imagePosition, .noImage)
        XCTAssertEqual(metricButton.title, "")
        XCTAssertNil(metricButton.image)
        XCTAssertEqual(metricStrip.segments.map(\.metric), [.networkDownload])
        XCTAssertEqual(metricStrip.segments.first?.symbol, "arrow.down")
        XCTAssertFalse(metricButton.toolTip?.contains("User") == true)
        XCTAssertFalse(metricButton.toolTip?.contains("System") == true)

        context.appModel.controlCenter.setMetricStyle(.compact)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.appModel.controlCenter.configuration.metricGroup.style, .compact)
        XCTAssertNil(controller.renderedStatusStates[.metricGroup]?.symbol)
        XCTAssertTrue(controller.statusItems[.metricGroup] === metricItem)
        XCTAssertNil(controller.metricStripViews[.metricGroup])
        let compactButton = try XCTUnwrap(metricItem.button)
        XCTAssertNil(compactButton.image)
        XCTAssertFalse(compactButton.title.contains("CPU"))

        context.appModel.controlCenter.setMetricStyle(.value)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(context.appModel.controlCenter.configuration.metricGroup.style, .value)
        XCTAssertTrue(
            controller.renderedStatusStates[.metricGroup]?.title.contains(
                MenuBarMetricID.networkDownload.title
            ) == true
        )
        let valueButton = try XCTUnwrap(metricItem.button)
        XCTAssertNil(valueButton.image)
        XCTAssertTrue(valueButton.title.contains(MenuBarMetricID.networkDownload.title))

        context.appModel.controlCenter.setMetricStyle(.iconAndValue)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(metricItem.button?.image)
        XCTAssertNotNil(controller.metricStripViews[.metricGroup])

        controller.stop()
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 0)
        context.appModel.controlCenter.setMetricStyle(.compact)
        XCTAssertTrue(controller.statusItems.isEmpty)
        await cleanup(context)
    }

    func testCombinedMetricDensityUsesSemanticSegmentsWithoutOverflowText() async throws {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: MenuPopoverStub.init,
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        context.appModel.controlCenter.setMetricGroupVisible(true)
        context.appModel.controlCenter.setMetricVisible(true, metric: .networkDownload)
        context.appModel.controlCenter.setMetricsAsSeparateItems(false)
        let metricItem = try XCTUnwrap(controller.statusItems[.metricGroup])
        let standardStrip = try XCTUnwrap(controller.metricStripViews[.metricGroup])

        XCTAssertEqual(standardStrip.segments.map(\.metric), [.cpu, .memory, .temperature])
        XCTAssertEqual(standardStrip.segments.map(\.leadingText), ["CPU", "RAM", nil])
        XCTAssertEqual(standardStrip.segments.map(\.symbol), [nil, nil, nil])
        XCTAssertFalse(controller.renderedStatusStates[.metricGroup]?.title.contains("+") == true)
        XCTAssertTrue(metricItem.button?.toolTip?.contains(MenuBarMetricID.networkDownload.title) == true)

        context.appModel.controlCenter.setMetricDensity(.compact)

        XCTAssertTrue(controller.statusItems[.metricGroup] === metricItem)
        XCTAssertTrue(controller.metricStripViews[.metricGroup] === standardStrip)
        XCTAssertEqual(standardStrip.segments.map(\.metric), [.cpu, .memory])

        context.appModel.controlCenter.setMetricsAsSeparateItems(true)
        let cpuButton = try XCTUnwrap(controller.statusItems[.metric(.cpu)]?.button)
        let memoryButton = try XCTUnwrap(controller.statusItems[.metric(.memory)]?.button)
        XCTAssertNil(cpuButton.image)
        XCTAssertNil(memoryButton.image)
        XCTAssertEqual(cpuButton.title, "")
        XCTAssertEqual(memoryButton.title, "")
        XCTAssertEqual(
            controller.metricStripViews[.metric(.cpu)]?.segments.first?.leadingText,
            "CPU"
        )
        XCTAssertEqual(
            controller.metricStripViews[.metric(.memory)]?.segments.first?.leadingText,
            "RAM"
        )
        XCTAssertEqual(controller.statusItems[.metric(.cpu)]?.length, 28)
        XCTAssertEqual(controller.statusItems[.metric(.memory)]?.length, 28)
        XCTAssertEqual(controller.statusItems[.metric(.temperature)]?.length, 40)
        XCTAssertNil(
            controller.metricStripViews[.metric(.temperature)]?.segments.first?.symbol
        )

        controller.stop()
        await cleanup(context)
    }

    func testWhenActiveClipboardItemAppearsOnlyForExceptionalRecordingState() async {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setMenuBarVisibility(.whenActive, for: .clipboard)
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: MenuPopoverStub.init,
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        XCTAssertNil(controller.statusItems[.feature(.clipboard)])

        context.appModel.clipboard.pauseRecording(minutes: 60)
        XCTAssertNotNil(controller.statusItems[.feature(.clipboard)])

        context.appModel.clipboard.resumeRecording()
        XCTAssertNil(controller.statusItems[.feature(.clipboard)])

        controller.stop()
        await cleanup(context)
    }

    func testWhenActiveInputToolItemsTrackTheirRuntimeState() async {
        let coordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let context = makeContext(inputEventTapCoordinator: coordinator)
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setMenuBarVisibility(.whenActive, for: .keyboardCleaning)
        context.appModel.controlCenter.setMenuBarVisibility(.whenActive, for: .scrollReverse)
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: MenuPopoverStub.init,
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        XCTAssertNil(controller.statusItems[.feature(.keyboardCleaning)])
        context.appModel.inputTools.keyboardCleaning.start()
        XCTAssertNotNil(controller.statusItems[.feature(.keyboardCleaning)])
        context.appModel.inputTools.keyboardCleaning.stop()
        XCTAssertNil(controller.statusItems[.feature(.keyboardCleaning)])

        XCTAssertNil(controller.statusItems[.feature(.scrollReverse)])
        context.appModel.inputTools.scrollReversal.isEnabled = true
        XCTAssertNotNil(controller.statusItems[.feature(.scrollReverse)])
        context.appModel.inputTools.scrollReversal.isEnabled = false
        XCTAssertNil(controller.statusItems[.feature(.scrollReverse)])

        controller.stop()
        await cleanup(context)
    }

    func testMetricStripMutatesOnlyChangedSegments() {
        let strip = MenuBarMetricStripView(frame: .zero)
        let cpu = MenuBarMetricSegmentState(
            metric: .cpu,
            symbol: "cpu",
            value: "12%",
            accessibilityLabel: "CPU 12%",
            width: 42
        )
        let memory = MenuBarMetricSegmentState(
            metric: .memory,
            symbol: "memorychip",
            value: "48%",
            accessibilityLabel: "Memory 48%",
            width: 42
        )
        strip.apply([cpu, memory])
        let cpuView = strip.segmentView(for: .cpu)
        let memoryView = strip.segmentView(for: .memory)

        strip.apply([
            MenuBarMetricSegmentState(
                metric: .cpu,
                symbol: "cpu",
                value: "13%",
                accessibilityLabel: "CPU 13%",
                width: 42
            ),
            memory
        ])

        XCTAssertEqual(cpuView?.mutationCount, 1)
        XCTAssertEqual(memoryView?.mutationCount, 0)
        XCTAssertTrue(strip.segmentView(for: .cpu) === cpuView)
        XCTAssertTrue(strip.segmentView(for: .memory) === memoryView)
    }

    func testAudioMixerStatusItemKeepsStableIconWhenMuteStateChanges() async throws {
        let mixerSuite = "MenuAudioMixerTests-\(UUID().uuidString)"
        let mixerDefaults = try XCTUnwrap(UserDefaults(suiteName: mixerSuite))
        addTeardownBlock {
            mixerDefaults.removePersistentDomain(forName: mixerSuite)
        }
        let mixer = AudioMixerController(
            discovery: MenuAudioDiscoveryStub(
                applications: [
                    AudioApplication(
                        id: 72,
                        processID: 720,
                        bundleID: "com.example.Audio",
                        name: "Audio App",
                        isProducingOutput: true,
                        volume: 100,
                        isMuted: false,
                        controlState: .native
                    )
                ]
            ),
            engine: MenuProcessAudioControllerStub(),
            browserBridge: MenuBrowserAudioBridgeStub(),
            defaults: mixerDefaults
        )
        await mixer.refreshApplications()
        let context = makeContext(audioMixerController: mixer)
        context.settings.globalShortcutEnabled = false
        context.appModel.controlCenter.setMenuBarVisibility(.whenActive, for: .audioMixer)
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: MenuPopoverStub.init,
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy()
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )
        let itemID = MenuBarItemID.feature(.audioMixer)
        XCTAssertNil(controller.statusItems[itemID])

        mixer.toggleMute(try XCTUnwrap(mixer.outputApplications.first))
        await settleMenuAction()

        XCTAssertTrue(mixer.isEverythingMuted)
        XCTAssertEqual(controller.renderedStatusStates[itemID]?.symbol, "slider.horizontal.3")
        XCTAssertEqual(controller.statusItems[itemID]?.length, NSStatusItem.squareLength)

        mixer.toggleMute(try XCTUnwrap(mixer.outputApplications.first))
        await settleMenuAction()
        XCTAssertNil(controller.statusItems[itemID])

        controller.stop()
        await cleanup(context)
    }

    func testApplicationWindowControllerOwnsVisibilityDemandAndPendingNoteClose() async {
        let context = makeContext()
        context.settings.globalShortcutEnabled = false
        let controller = ApplicationWindowController(
            appModel: context.appModel,
            makeWindow: MenuPanelStub.init,
            makeContentViewController: { _ in NSViewController() }
        )

        XCTAssertFalse(controller.isWindowVisible)
        context.appModel.showClipboard()
        controller.showControlCenter()
        XCTAssertTrue(controller.isWindowVisible)
        XCTAssertEqual(context.appModel.router.activeFeature, .controlCenter)

        controller.windowDidMiniaturize(
            Notification(name: NSWindow.didMiniaturizeNotification)
        )
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 0)
        controller.windowDidDeminiaturize(
            Notification(name: NSWindow.didDeminiaturizeNotification)
        )

        context.appModel.showQuickNote()
        context.appModel.notes.draftBody = "Save before closing the application window"
        let noteWindow = MenuPanelStub()
        XCTAssertFalse(controller.windowShouldClose(noteWindow))
        XCTAssertFalse(controller.windowShouldClose(noteWindow))
        for _ in 0..<100 where context.appModel.notes.hasPendingChanges {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(context.appModel.notes.hasPendingChanges)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.windowShouldClose(noteWindow))

        controller.showActiveFeature()
        XCTAssertTrue(controller.isWindowVisible)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(context.appModel.systemMetrics.demandCount, 0)
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.isWindowVisible)
        noteWindow.delegate = nil
        noteWindow.close()
        let defaultFactoryController = ApplicationWindowController(appModel: context.appModel)
        defaultFactoryController.stop()
        await cleanup(context)
    }

    func testFeatureStatusItemsRunEveryLeftClickBranchAndTogglePresentation() async throws {
        let context = makeContext(
            inputEventTapCoordinator: InputEventTapCoordinatorStub(isTrusted: true)
        )
        context.settings.globalShortcutEnabled = false
        for id in UtilityFeatureID.allCases {
            context.appModel.controlCenter.setStandaloneItemVisible(true, for: id)
        }
        let popover = MenuPopoverStub()
        let controller = MenuBarController(
            appModel: context.appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                removeStatusItem: { NSStatusBar.system.removeStatusItem($0) },
                makePopover: { popover },
                makePanel: { _ in MenuPanelStub() },
                quickLookPresenter: MenuQuickLookSpy(),
                currentEvent: { nil }
            ),
            panelEventMonitor: MenuPanelEventMonitorStub()
        )

        func click(_ id: UtilityFeatureID) throws {
            try XCTUnwrap(controller.statusItems[.feature(id)]?.button).performClick(nil)
        }

        context.appModel.controlCenter.setClickAction(.open, for: .clipboard)
        try click(.clipboard)
        await settleMenuAction()
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(context.appModel.router.activeFeature, .clipboard)
        try click(.clipboard)
        await settleMenuAction()
        XCTAssertFalse(popover.isShown)

        context.appModel.controlCenter.setClickAction(.newNote, for: .notes)
        try click(.notes)
        await settleMenuAction()
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(context.appModel.notes.screen, .editor)
        try click(.notes)
        await settleMenuAction()
        XCTAssertTrue(popover.isShown)
        context.appModel.notes.discardChanges()
        context.appModel.controlCenter.setClickAction(.open, for: .notes)
        try click(.notes)
        await settleMenuAction()
        XCTAssertFalse(popover.isShown)

        context.appModel.controlCenter.setClickAction(
            .toggleClipboardRecording,
            for: .clipboard
        )
        try click(.clipboard)
        await settleMenuAction()
        XCTAssertTrue(context.viewModel.isPaused)
        try click(.clipboard)
        await settleMenuAction()
        XCTAssertFalse(context.viewModel.isPaused)

        try click(.keyboardCleaning)
        await settleMenuAction()
        XCTAssertTrue(context.appModel.inputTools.keyboardCleaning.isActive)
        try click(.keyboardCleaning)
        await settleMenuAction()
        XCTAssertFalse(context.appModel.inputTools.keyboardCleaning.isActive)

        context.appModel.controlCenter.setClickAction(.toggleScrollReverse, for: .scrollReverse)
        try click(.scrollReverse)
        await settleMenuAction()
        XCTAssertTrue(context.appModel.inputTools.scrollReversal.isActive)

        context.appModel.controlCenter.setClickAction(.muteAllAudio, for: .audioMixer)
        try click(.audioMixer)
        await settleMenuAction()
        XCTAssertFalse(popover.isShown)

        controller.stop()
        await cleanup(context)
    }

    private func rightMouseEvent() -> NSEvent? {
        NSEvent.mouseEvent(
            with: .rightMouseUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
    }

    private func performMenuAction(_ item: NSMenuItem) {
        guard let action = item.action else {
            return XCTFail("Expected an actionable menu item")
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }

    private func settleMenuAction() async {
        for _ in 0..<4 { await Task.yield() }
    }

    private struct Context {
        let directory: URL
        let suite: String
        let storage: StorageService
        let settings: AppSettings
        let appModel: AppModel
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext(
        audioMixerController: AudioMixerController? = nil,
        inputEventTapCoordinator: (any InputEventTapCoordinating)? = nil
    ) -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "MenuBarControllerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suite = "MenuBarControllerDefaults-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("MenuBarController-\(UUID().uuidString)"))
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: MenuPasteServiceStub(),
            settings: settings,
            inputEventTapCoordinator: inputEventTapCoordinator,
            audioMixerController: audioMixerController,
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: UserDefaults(suiteName: suite)!)
            ),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            suite: suite,
            storage: storage,
            settings: settings,
            appModel: appModel,
            viewModel: appModel.clipboard
        )
    }

    private func cleanup(_ context: Context) async {
        context.appModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.suite)
        try? FileManager.default.removeItem(at: context.directory)
    }

}

@MainActor
private final class MenuApplicationWindowPresenterSpy: ApplicationWindowPresenting {
    private(set) var isWindowVisible = false
    private(set) var showControlCenterCount = 0
    private(set) var showActiveFeatureCount = 0

    func showControlCenter() {
        showControlCenterCount += 1
        isWindowVisible = true
    }

    func showActiveFeature() {
        showActiveFeatureCount += 1
        isWindowVisible = true
    }

    func stop() {
        isWindowVisible = false
    }
}

private final class MenuAudioDiscoveryStub: AudioProcessDiscovering, @unchecked Sendable {
    let discoveredApplications: [AudioApplication]

    init(applications: [AudioApplication]) {
        discoveredApplications = applications
    }

    func applications() async -> [AudioApplication] {
        discoveredApplications
    }
}

@MainActor
private final class MenuProcessAudioControllerStub: ProcessAudioControlling {
    func setFailureHandler(
        _ handler: (@MainActor @Sendable (String, Error) -> Void)?
    ) {}

    func setGain(
        _ gain: Double,
        for processObjectIDs: Set<AudioObjectID>,
        bundleID: String
    ) throws {}

    func stopControlling(bundleID: String) {}
    func stopAll() {}
}

@MainActor
private final class MenuBrowserAudioBridgeStub: BrowserAudioBridging {
    var tabsDidChange: (([BrowserAudioTab]) -> Void)?
    var connectionMessageDidChange: ((String?) -> Void)?

    func start() {}
    func stop() {}
    func setVolume(_ volume: Double, tabID: String) {}
    func activate(tabID: String) {}
}

@MainActor
private final class MenuPopoverStub: NSPopover {
    private var presented = false
    var presentationFailuresRemaining = 0
    var didShow: (() -> Void)?
    private(set) var showCallCount = 0
    private(set) var recordedPositioningRect: NSRect?
    private(set) weak var positioningView: NSView?
    private(set) var recordedPreferredEdge: NSRectEdge?

    override var isShown: Bool { presented }

    override func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        showCallCount += 1
        recordedPositioningRect = positioningRect
        self.positioningView = positioningView
        recordedPreferredEdge = preferredEdge
        if presentationFailuresRemaining > 0 {
            presentationFailuresRemaining -= 1
            return
        }
        presented = true
        delegate?.popoverWillShow?(Notification(name: NSPopover.willShowNotification, object: self))
        didShow?()
    }

    override func performClose(_ sender: Any?) {
        presented = false
    }

    override func close() {
        presented = false
    }
}

@MainActor
private final class MenuPanelStub: NSPanel {
    private var presented = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override var isVisible: Bool { presented }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        presented = true
    }

    override func orderOut(_ sender: Any?) {
        presented = false
    }

    override func close() {
        presented = false
    }

    override func setFrameOrigin(_ point: NSPoint) {}
}

@MainActor
private final class MenuQuickLookSpy: QuickLookPresenting {
    private(set) var shownItems: [ClipboardItem] = []
    private(set) var closeCount = 0

    func show(item: ClipboardItem, storage: StorageService) {
        shownItems.append(item)
    }

    func close() {
        closeCount += 1
    }
}

@MainActor
private final class MenuPasteServiceStub: ActiveApplicationPasting {
    func captureTargetApplication() {}
    func paste() async -> ActiveApplicationPasteResult { .pasted }
}

@MainActor
private final class MenuPanelEventMonitorStub: PanelEventMonitoring {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { nil }
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    func removeMonitor(_ monitor: Any) {}
}

@MainActor
private final class MenuRecordingPanelEventMonitor: PanelEventMonitoring {
    private var localHandler: ((NSEvent) -> NSEvent?)?

    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { NSObject() }

    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        localHandler = handler
        return NSObject()
    }

    func removeMonitor(_ monitor: Any) {}

    func fireLocal(_ event: NSEvent) -> NSEvent? {
        localHandler?(event)
    }
}

@MainActor
private final class MenuShortcutBackendStub: GlobalShortcutBackend {
    var eventAction: ((UInt32) -> Void)?
    private(set) var installCount = 0
    private(set) var registerCount = 0

    func installEventHandler() -> OSStatus {
        installCount += 1
        return noErr
    }

    func register(shortcut: GlobalShortcut) -> OSStatus {
        registerCount += 1
        return noErr
    }

    func unregister() {}

    func fire(_ kind: UInt32) {
        eventAction?(kind)
    }
}
