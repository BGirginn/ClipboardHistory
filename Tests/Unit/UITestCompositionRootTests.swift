import AppKit
import CoreAudio
import XCTest
@testable import ClipboardHistoryTestHost

@MainActor
final class UITestCompositionRootTests: XCTestCase {
    func testCompositionRootRejectsSharedDefaultsAndBuildsAnIsolatedModel() async throws {
        XCTAssertNil(UITestCompositionRoot.makeModel(environment: [
            "CLIPBOARD_HISTORY_TEST_DEFAULTS": "unsafe-suite"
        ]))

        let identifier = UUID().uuidString
        let root = URL(fileURLWithPath: "/private/tmp/ClipboardHistory-\(identifier)")
        let suite = "ClipboardHistory.Coverage.\(identifier)"
        let model = try XCTUnwrap(UITestCompositionRoot.makeModel(environment: [
            "CLIPBOARD_HISTORY_TEST_ROOT": root.path,
            "CLIPBOARD_HISTORY_TEST_DEFAULTS": suite
        ]))

        XCTAssertEqual(model.uiTestRoot, root)
        XCTAssertFalse(model.settings.closePanelAfterCopying)
        model.prepareForShutdown()
        await model.clipboard.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func testUITestServicesExerciseEverySafeAdapterBoundary() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClipboardHistory-\(UUID().uuidString)")
        let fileManager = UITestFileManager(root: root)
        XCTAssertEqual(fileManager.temporaryDirectory, root)

        let services = UITestSystemServices()
        XCTAssertEqual(services.installEventHandler(), noErr)
        XCTAssertEqual(services.register(shortcut: .defaultShortcut), noErr)
        services.unregister()
        services.captureTargetApplication()
        let pasteResult = await services.paste()
        let authenticated = try await services.authenticate(reason: "test")
        XCTAssertEqual(pasteResult, .targetUnavailable)
        XCTAssertTrue(authenticated)
        XCTAssertTrue(services.requestAccessibilityAccess())
        XCTAssertTrue(services.setKeyboardBlocking(true))
        XCTAssertTrue(services.setScrollReversal(.disabled))
        XCTAssertTrue(services.maintain())
        services.stopAll()
        services.openAccessibilitySettings()
        try services.setEnabled(true)
        XCTAssertTrue(services.isEnabled)
        services.start()
        services.stop()
        services.setVolume(0.5, tabID: "tab")
        services.activate(tabID: "tab")
        try services.setGain(0.5, for: Set<AudioObjectID>(), bundleID: "fixture")
        services.stopControlling(bundleID: "fixture")
        let applications = await services.applications()
        let sample = await services.sample(at: .distantPast)
        XCTAssertTrue(applications.isEmpty)
        XCTAssertEqual(sample.timestamp, .distantPast)
        services.reveal([])
    }
}
