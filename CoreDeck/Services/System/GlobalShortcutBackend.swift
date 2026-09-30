import Carbon
import Foundation

@MainActor
protocol GlobalShortcutBackend: AnyObject {
    var eventAction: ((UInt32) -> Void)? { get set }
    func installEventHandler() -> OSStatus
    func register(shortcut: GlobalShortcut) -> OSStatus
    func unregister()
}
