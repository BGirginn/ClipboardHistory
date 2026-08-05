import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutMonitor: ObservableObject {
    @Published private(set) var registrationError: String?

    private let pressAction: @MainActor () -> Void
    private let releaseAction: @MainActor () -> Void
    private let backend: any GlobalShortcutBackend
    private(set) var isPressed = false
    private var shortcut = GlobalShortcut.defaultShortcut

    init(
        action: @escaping @MainActor () -> Void,
        releaseAction: @escaping @MainActor () -> Void = {},
        backend: any GlobalShortcutBackend = SystemGlobalShortcutBackend()
    ) {
        pressAction = action
        self.releaseAction = releaseAction
        self.backend = backend
        backend.eventAction = { [weak self] kind in
            self?.handleHotKeyEvent(kind: kind)
        }
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
        backend.unregister()
    }

    private func register() {
        let handlerStatus = backend.installEventHandler()
        guard handlerStatus == noErr else {
            registrationError = String(localized: "Unable to install the global shortcut handler (\(handlerStatus)).")
            return
        }

        let status = backend.register(shortcut: shortcut)
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
