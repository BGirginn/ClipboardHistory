import Carbon
import Foundation

@MainActor
protocol GlobalShortcutBackend: AnyObject {
    var eventAction: ((UInt32) -> Void)? { get set }
    func installEventHandler() -> OSStatus
    func register(shortcut: GlobalShortcut) -> OSStatus
    func unregister()
}

@MainActor
final class SystemGlobalShortcutBackend: GlobalShortcutBackend {
    var eventAction: ((UInt32) -> Void)?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    static let carbonEventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        let backend = Unmanaged<SystemGlobalShortcutBackend>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let kind = GetEventKind(event)
        MainActor.assumeIsolated { backend.eventAction?(kind) }
        return noErr
    }

    func installEventHandler() -> OSStatus {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        return InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func register(shortcut: GlobalShortcut) -> OSStatus {
        let identifier = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        return RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
