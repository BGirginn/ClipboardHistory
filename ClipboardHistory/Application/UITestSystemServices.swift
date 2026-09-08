#if CLIPBOARD_HISTORY_TEST_HOST
import AppKit
import CoreAudio
import Carbon
import Foundation

@MainActor
final class UITestSystemServices: InputEventTapCoordinating, LaunchAtLoginBackend,
    BrowserAudioBridging, ProcessAudioControlling, AudioProcessDiscovering,
    SystemMetricsProviding, WorkspaceRevealing, ActiveApplicationPasting,
    SystemAuthenticating, GlobalShortcutBackend {
    var eventAction: ((UInt32) -> Void)?
    func installEventHandler() -> OSStatus { noErr }
    func register(shortcut: GlobalShortcut) -> OSStatus { noErr }
    func unregister() { }
    func captureTargetApplication() { }
    func paste() async -> ActiveApplicationPasteResult { .targetUnavailable }
    func authenticate(reason: String) async throws -> Bool { true }
    var isTrusted = true
    var isEnabled = false
    var interruptionHandler: (@MainActor () -> Void)?
    var tabsDidChange: (([BrowserAudioTab]) -> Void)?
    var connectionMessageDidChange: ((String?) -> Void)?
    func requestAccessibilityAccess() -> Bool { isTrusted }
    func setKeyboardBlocking(_ enabled: Bool) -> Bool { true }
    func setScrollReversal(_ configuration: ScrollReversalConfiguration) -> Bool { true }
    func maintain() -> Bool { true }
    func stopAll() { }
    func openAccessibilitySettings() { }
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
    func start() { }
    func stop() { }
    func setVolume(_ volume: Double, tabID: String) { }
    func activate(tabID: String) { }
    func setGain(_ gain: Double, for processObjectIDs: Set<AudioObjectID>, bundleID: String) throws { }
    func stopControlling(bundleID: String) { }
    func applications() async -> [AudioApplication] { [] }
    func sample(at date: Date) async -> SystemMetricSnapshot {
        var sample = SystemMetricSnapshot.empty
        sample.timestamp = date
        return sample
    }
    func reveal(_ urls: [URL]) { }
}
#endif
