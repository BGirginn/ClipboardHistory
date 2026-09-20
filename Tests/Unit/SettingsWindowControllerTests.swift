import AppKit
import XCTest
@testable import ClipboardHistoryTestHost

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testControllerReusesWindowAndPreservesLastSelection() {
        var makeWindowCount = 0
        let model = AppModel(startsAutomatically: false)
        let controller = SettingsWindowController(
            appModel: model,
            makeWindow: {
                makeWindowCount += 1
                return NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
            }
        )

        controller.show(section: .notes)
        XCTAssertEqual(controller.presentedSubsection, .notesGeneral)
        controller.close()
        controller.show(section: nil)

        XCTAssertEqual(makeWindowCount, 1)
        XCTAssertEqual(controller.presentedSubsection, .notesGeneral)
        XCTAssertTrue(controller.isWindowVisible)
        controller.stop()
    }

    func testAppModelUsesInjectedSettingsPresenterWithoutChangingMainRoute() {
        let model = AppModel(startsAutomatically: false)
        var requestedSection: AppSettingsSection?
        var closeCount = 0
        model.requestOpenSettings = { requestedSection = $0 }
        model.requestCloseSettings = { closeCount += 1 }

        model.openSettings(section: .audioMixer)
        model.closeSettings()

        XCTAssertEqual(requestedSection, .audioMixer)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(model.router.activeFeature, .controlCenter)
    }
}
