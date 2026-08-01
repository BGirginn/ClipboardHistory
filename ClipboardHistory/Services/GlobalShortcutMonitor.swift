import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutMonitor: ObservableObject {
    @Published private(set) var registrationError: String?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let pressAction: @MainActor () -> Void
    private let releaseAction: @MainActor () -> Void
    private(set) var isPressed = false
    private var shortcut = GlobalShortcut.defaultShortcut

    init(
        action: @escaping @MainActor () -> Void,
        releaseAction: @escaping @MainActor () -> Void = {}
    ) {
        pressAction = action
        self.releaseAction = releaseAction
    }

    func setEnabled(_ enabled: Bool, shortcut: GlobalShortcut? = nil) {
        unregister()
        if let shortcut { self.shortcut = shortcut }
        guard enabled else {
            registrationError = nil
            return
        }
        register()
    }

    func unregister() {
        isPressed = false
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register() {
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
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)
                MainActor.assumeIsolated { monitor.handleHotKeyEvent(kind: kind) }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            userData,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            registrationError = String(localized: "Unable to install the global shortcut handler (\(handlerStatus)).")
            return
        }

        let identifier = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            registrationError = status == eventHotKeyExistsErr
                ? String(localized: "\(shortcut.title) is already registered by another application.")
                : String(localized: "Global shortcut registration failed (\(status)).")
            unregister()
            AppLog.lifecycle.error("Global shortcut registration failed; status=\(status)")
        } else {
            registrationError = nil
        }
    }

    func handleHotKeyEvent(kind: UInt32) {
        switch kind {
        case UInt32(kEventHotKeyPressed):
            guard !isPressed else { return }
            isPressed = true
            pressAction()
        case UInt32(kEventHotKeyReleased):
            guard isPressed else { return }
            isPressed = false
            releaseAction()
        default:
            break
        }
    }

    func cancelHeldShortcut() {
        isPressed = false
    }
}
