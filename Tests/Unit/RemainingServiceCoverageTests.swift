import AppKit
import Foundation
import XCTest

@testable import ClipboardHistory

@MainActor
final class RemainingServiceCoverageTests: XCTestCase {
    func testClipboardWriterCoversDirectBinaryContentAndLegacyPayloadFallbacks() async throws {
        let root = temporaryDirectory("ClipboardWriterCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("ClipboardWriterCoverage-\(UUID().uuidString)"))
        let writer = ClipboardPasteboardWriter(pasteboard: pasteboard)
        let png = try makeCoveragePNG()
        let pdf = Data("%PDF-1.7\nwriter".utf8)
        let file = root.appending(path: "file.txt")
        try Data("file".utf8).write(to: file)

        let wroteImage = await writer.write(
            content: .images(pngData: [png], hash: "image", sourceBundleIdentifier: nil),
            representation: .original
        )
        XCTAssertTrue(wroteImage)
        let wrotePDF = await writer.write(
            content: .pdf(data: pdf, hash: "pdf", sourceBundleIdentifier: nil),
            representation: .original
        )
        XCTAssertTrue(wrotePDF)
        let wroteFiles = await writer.write(
            content: .files(
                urls: [file],
                bookmarks: [],
                hash: "files",
                sourceBundleIdentifier: nil
            ),
            representation: .original
        )
        XCTAssertTrue(wroteFiles)

        let metadataItem = ClipboardItem(
            type: .text,
            text: "original",
            hash: "metadata",
            protectedMetadata: .init(extractedText: "extracted")
        )
        let wroteMetadata = await writer.write(
            item: metadataItem,
            storage: storage,
            representation: .plainText
        )
        XCTAssertTrue(wroteMetadata)
        XCTAssertEqual(pasteboard.string(forType: .string), "extracted")

        let richID = UUID()
        let storedHTML = await storage.storePayload(
            Data("<b>legacy html</b>".utf8),
            id: richID,
            extension: "html",
            encrypt: false
        )
        let htmlName = try XCTUnwrap(storedHTML)
        let htmlItem = ClipboardItem(
            id: richID,
            type: .richText,
            text: "legacy html",
            hash: "legacy-html",
            payloadFilename: htmlName
        )
        let wroteHTML = await writer.write(item: htmlItem, storage: storage, representation: .html)
        XCTAssertTrue(wroteHTML)
        XCTAssertNotNil(pasteboard.data(forType: .html))

        let rtfID = UUID()
        let storedRTF = await storage.storePayload(
            Data("{\\rtf1 legacy}".utf8),
            id: rtfID,
            extension: "rtf",
            encrypt: false
        )
        let rtfName = try XCTUnwrap(storedRTF)
        let rtfItem = ClipboardItem(
            id: rtfID,
            type: .richText,
            text: "legacy rtf",
            hash: "legacy-rtf",
            payloadFilename: rtfName
        )
        let wroteRTF = await writer.write(item: rtfItem, storage: storage, representation: .richText)
        XCTAssertTrue(wroteRTF)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))

        let bookmark = try file.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let bookmarked = ClipboardItem(
            type: .files,
            hash: "bookmark",
            fileURLs: [],
            fileBookmarks: [bookmark]
        )
        let wroteBookmark = await writer.write(
            item: bookmarked,
            storage: storage,
            representation: .original
        )
        XCTAssertTrue(wroteBookmark)
        XCTAssertEqual(writer.changeCount, pasteboard.changeCount)
        await storage.close()
    }

    func testLocalMigrationFileSystemAndSystemPanelMonitorBoundaries() throws {
        let root = temporaryDirectory("MigrationFileSystemCoverage")
        let source = root.appending(path: "source")
        let destination = root.appending(path: "destination")
        let directory = root.appending(path: "directory", directoryHint: .isDirectory)
        let link = root.appending(path: "link")
        defer { try? FileManager.default.removeItem(at: root) }

        let fileSystem = LocalMigrationFileSystem()
        try fileSystem.createDirectory(at: directory)
        try Data("move".utf8).write(to: source)
        try fileSystem.moveItem(at: source, to: destination)
        XCTAssertTrue(fileSystem.fileExists(at: destination))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        XCTAssertTrue(try fileSystem.isSymbolicLink(at: link))
        try fileSystem.removeItem(at: destination)
        XCTAssertFalse(fileSystem.fileExists(at: destination))

        let monitor = SystemPanelEventMonitor()
        let local = monitor.addLocalMonitor { $0 }
        let global = monitor.addGlobalMonitor { _ in }
        if let local { monitor.removeMonitor(local) }
        if let global { monitor.removeMonitor(global) }
    }

    func testSecretEmptyInputAndTextThumbnailHaveNoOutput() async throws {
        let detection = SecretDetectionService().detect(in: "", sourceBundleIdentifier: nil)
        XCTAssertFalse(detection.isSensitive)
        XCTAssertEqual(detection.confidence, 0)
        XCTAssertTrue(detection.signals.isEmpty)

        let root = temporaryDirectory("TextThumbnailCoverage")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let service = ThumbnailService()
        let text = ClipboardItem(type: .text, text: "text", hash: "text-thumbnail")
        let thumbnail = await service.thumbnailData(for: text, storage: storage)
        XCTAssertNil(thumbnail)

        let png = try makeCoveragePNG()
        let imageID = UUID()
        let filename = await storage.storeImage(png, id: imageID)
        let failingCreator = ThumbnailService(imageThumbnailCreator: { _, _, _ in nil })
        let failedThumbnail = await failingCreator.thumbnailData(
            for: ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: filename,
                hash: "forced-thumbnail-failure"
            ),
            storage: storage
        )
        XCTAssertNil(failedThumbnail)
        await storage.close()
    }

    func testAccessibilityTrustChecksUseInjectedEvaluatorsWithoutSystemPrompts() {
        var promptedOptions: CFDictionary?
        let trusted = SystemAccessibilityPasteBackend(
            promptedTrustEvaluator: { options in
                promptedOptions = options
                return true
            },
            trustEvaluator: { false }
        )

        XCTAssertTrue(trusted.isTrusted(prompt: true))
        XCTAssertNotNil(promptedOptions)
        XCTAssertFalse(trusted.isTrusted(prompt: false))
    }

    func testInputEventTapTrustChecksUseInjectedEvaluatorsWithoutSystemPrompt() {
        var promptedOptions: CFDictionary?
        var openedSettingsURL: URL?
        let coordinator = SystemInputEventTapCoordinator(
            promptedTrustEvaluator: { options in
                promptedOptions = options
                return true
            },
            trustEvaluator: { false },
            accessibilitySettingsOpener: { openedSettingsURL = $0 }
        )

        XCTAssertFalse(coordinator.isTrusted)
        XCTAssertTrue(coordinator.requestAccessibilityAccess())
        XCTAssertNotNil(promptedOptions)
        XCTAssertFalse(coordinator.setKeyboardBlocking(true))
        XCTAssertTrue(coordinator.maintain())
        coordinator.openAccessibilitySettings()
        XCTAssertEqual(openedSettingsURL?.scheme, "x-apple.systempreferences")

        let keyboardMask = SystemInputEventTapCoordinator.eventMask(
            for: InputEventTapConfiguration(blocksKeyboard: true)
        )
        XCTAssertNotEqual(keyboardMask & (CGEventMask(1) << CGEventType.keyDown.rawValue), 0)
        XCTAssertNotEqual(keyboardMask & (CGEventMask(1) << 14), 0)
        let scrollMask = SystemInputEventTapCoordinator.eventMask(
            for: InputEventTapConfiguration(
                scrollReversal: ScrollReversalConfiguration(
                    isEnabled: true,
                    reversesDiscreteVertical: true,
                    reversesDiscreteHorizontal: false,
                    reversesPreciseVertical: false,
                    reversesPreciseHorizontal: false
                )
            )
        )
        XCTAssertNotEqual(
            scrollMask & (CGEventMask(1) << CGEventType.scrollWheel.rawValue),
            0
        )
        XCTAssertEqual(
            SystemInputEventTapCoordinator.eventMask(for: InputEventTapConfiguration()),
            0
        )
        var interruptionCount = 0
        coordinator.interruptionHandler = { interruptionCount += 1 }
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ) else { return XCTFail("Expected a synthetic keyboard event") }
        XCTAssertNotNil(coordinator.filter(type: .tapDisabledByTimeout, event: event))
        XCTAssertEqual(interruptionCount, 1)
        coordinator.handleUnrecoverableInterruption()
        XCTAssertEqual(interruptionCount, 2)
        coordinator.stopAll()
    }

    func testLoggerSubsystemIsAvailable() {
        XCTAssertFalse(AppLog.subsystem.isEmpty)
    }

    func testNativeReadOnlySensorAndAudioDiscoveryAdaptersSmoke() {
        let temperatureProvider = AppleSMCTemperatureProvider()
        for reading in temperatureProvider.readings() + temperatureProvider.readings() {
            XCTAssertTrue((10...130).contains(reading.celsius), "temperature range")
            XCTAssertFalse(reading.id.isEmpty, "temperature identifier")
            XCTAssertFalse(reading.name.isEmpty, "temperature name")
        }

        let discovery = CoreAudioProcessDiscovery()
        discovery.startObservingChanges {}
        let applications = discovery.applications()
        discovery.stopObservingChanges()
        discovery.stopObservingChanges()
        for application in applications {
            XCTAssertFalse(application.bundleID.isEmpty, "audio bundle identifier")
            XCTAssertFalse(application.processObjectIDs.contains(0), "audio object identifier")
            XCTAssertEqual(
                application.id,
                application.processObjectIDs.min(),
                "stable grouped audio identifier"
            )
        }
    }

    func testApplicationDelegateNormalLaunchAndTerminationUseInjectedFactories() async {
        let root = temporaryDirectory("ApplicationDelegateCoverage")
        let suite = "ApplicationDelegateCoverage-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let settings = AppSettings(defaults: defaults)
        settings.globalShortcutEnabled = false
        let storage = StorageService(baseDirectory: root, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("ApplicationDelegateCoverage-\(UUID().uuidString)"))
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: settings,
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: defaults)
            ),
            startsAutomatically: false
        )
        var appModelFactoryCount = 0
        var controllerFactoryCount = 0
        var createdController: MenuBarController?
        let delegate = ClipboardHistoryAppDelegate(
            environment: [:],
            appModelFactory: {
                appModelFactoryCount += 1
                return appModel
            },
            menuBarControllerFactory: { providedAppModel in
                controllerFactoryCount += 1
                XCTAssertTrue(providedAppModel === appModel)
                let controller = MenuBarController(
                    appModel: providedAppModel,
                    panelEventMonitor: ApplicationDelegatePanelEventMonitorStub()
                )
                createdController = controller
                return controller
            }
        )

        appModel.showClipboard()
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        XCTAssertEqual(appModelFactoryCount, 1)
        XCTAssertEqual(controllerFactoryCount, 1)
        await waitUntil("normal launch routes to Control Center") {
            appModel.router.activeFeature == .controlCenter
        }
        XCTAssertEqual(appModel.router.activeFeature, .controlCenter)

        createdController?.closePopover()
        appModel.showClipboard()
        XCTAssertFalse(
            delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false)
        )
        await waitUntil("Finder reopen routes to Control Center") {
            appModel.router.activeFeature == .controlCenter
        }
        XCTAssertEqual(appModel.router.activeFeature, .controlCenter)
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        var backgroundController: MenuBarController?
        var terminationReplies: [Bool] = []
        let terminationExpectation = expectation(description: "shutdown reply")
        let backgroundDelegate = ClipboardHistoryAppDelegate(
            environment: [:],
            arguments: ["--background-launch"],
            appModelFactory: { appModel },
            menuBarControllerFactory: { model in
                let controller = MenuBarController(
                    appModel: model,
                    panelEventMonitor: ApplicationDelegatePanelEventMonitorStub()
                )
                backgroundController = controller
                return controller
            },
            terminationReply: { _, canTerminate in
                terminationReplies.append(canTerminate)
                terminationExpectation.fulfill()
            }
        )
        appModel.showClipboard()
        backgroundDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await Task.yield()
        XCTAssertFalse(backgroundController?.isPopoverShown == true)
        XCTAssertEqual(appModel.router.activeFeature, .clipboard)
        XCTAssertEqual(backgroundDelegate.applicationShouldTerminate(.shared), .terminateLater)
        XCTAssertEqual(backgroundDelegate.applicationShouldTerminate(.shared), .terminateLater)
        await fulfillment(of: [terminationExpectation], timeout: 2)
        XCTAssertEqual(terminationReplies, [true])
        backgroundDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
    }

    func testApplicationDelegateCancelsQuitForUnsavedNoteThenAllowsRetry() async {
        let root = temporaryDirectory("ApplicationDelegateFailedQuit")
        let suite = "ApplicationDelegateFailedQuit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let storage = StorageService(
            baseDirectory: root,
            operationFailureInjector: { operation in
                guard case let .prepareSQL(sql) = operation,
                      sql.contains("INSERT OR REPLACE INTO Notes") else { return }
                throw CocoaError(.fileWriteUnknown)
            }
        )
        let appModel = AppModel(
            storage: storage,
            settings: AppSettings(defaults: defaults),
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: defaults)
            ),
            startsAutomatically: false
        )
        let popover = ApplicationDelegatePopoverStub()
        let controller = MenuBarController(
            appModel: appModel,
            dependencies: MenuBarControllerDependencies(
                makeStatusItem: {
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                },
                makePopover: { popover },
                makePanel: { _ in NSPanel() },
                quickLookPresenter: QuickLookService()
            ),
            panelEventMonitor: ApplicationDelegatePanelEventMonitorStub(),
            popoverAnchor: { NSView() }
        )
        var replies: [Bool] = []
        let blockedReply = expectation(description: "blocked shutdown reply")
        let delegate = ClipboardHistoryAppDelegate(
            environment: [:],
            arguments: ["--background-launch"],
            appModelFactory: { appModel },
            menuBarControllerFactory: { _ in controller },
            terminationReply: { _, canTerminate in
                replies.append(canTerminate)
                blockedReply.fulfill()
            }
        )
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        appModel.showQuickNote()
        appModel.notes.draftBody = "must survive a failed quit"

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            NSApplication.TerminateReply.terminateLater
        )
        await fulfillment(of: [blockedReply], timeout: 2)
        XCTAssertEqual(replies, [false])
        XCTAssertEqual(appModel.router.activeFeature, .notes)
        XCTAssertTrue(controller.isPopoverShown)

        appModel.notes.discardChanges()
        let successfulReply = expectation(description: "successful retry reply")
        replies.removeAll()
        let retryDelegate = ClipboardHistoryAppDelegate(
            environment: [:],
            arguments: ["--background-launch"],
            appModelFactory: { appModel },
            menuBarControllerFactory: { _ in controller },
            terminationReply: { _, canTerminate in
                replies.append(canTerminate)
                successfulReply.fulfill()
            }
        )
        retryDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        XCTAssertEqual(
            retryDelegate.applicationShouldTerminate(NSApplication.shared),
            NSApplication.TerminateReply.terminateLater
        )
        await fulfillment(of: [successfulReply], timeout: 2)
        XCTAssertEqual(replies, [true])
        retryDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func waitUntil(
        _ label: String,
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Condition did not become true: \(label)")
    }

    private func makeCoveragePNG() throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
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
            )
        )
        bitmap.setColor(.systemPurple, atX: 0, y: 0)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ApplicationDelegatePanelEventMonitorStub: PanelEventMonitoring {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any? { nil }
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    func removeMonitor(_ monitor: Any) {}
}

@MainActor
private final class ApplicationDelegatePopoverStub: NSPopover {
    private var presented = false

    override var isShown: Bool { presented }

    override func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        presented = true
    }

    override func performClose(_ sender: Any?) {
        presented = false
    }

    override func close() {
        presented = false
    }
}
