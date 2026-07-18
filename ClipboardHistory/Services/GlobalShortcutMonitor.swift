import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutMonitor: ObservableObject {
    @Published private(set) var registrationError: String?

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func setEnabled(_ enabled: Bool) {
        unregister()
        guard enabled else {
            registrationError = nil
            return
        }
        register()
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

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.action() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            registrationError = "Unable to install the global shortcut handler (\(handlerStatus))."
            return
        }

        let identifier = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            registrationError = status == eventHotKeyExistsErr
                ? "Command-Shift-V is already registered by another application."
                : "Global shortcut registration failed (\(status))."
            unregister()
            AppLog.lifecycle.error("Global shortcut registration failed; status=\(status)")
        } else {
            registrationError = nil
        }
    }
}
