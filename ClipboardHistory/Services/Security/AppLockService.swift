import AppKit
import Combine
import Foundation

@MainActor
final class AppLockService: NSObject, ObservableObject {
    @Published private(set) var state: ApplicationLockState = .disabled
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAuthenticating = false

    private var option: AutoLockOption = .never
    private var inactivityTask: Task<Void, Never>?
    private let authenticator: any SystemAuthenticating
    private let sleepClock: any SleepClock
    private let lockNotificationCenter: NotificationCenter

    override convenience init() {
        self.init(
            authenticator: LocalSystemAuthenticator(),
            sleepClock: SystemSleepClock(),
            lockNotificationCenter: NSWorkspace.shared.notificationCenter
        )
    }

    init(
        authenticator: any SystemAuthenticating,
        sleepClock: any SleepClock = SystemSleepClock(),
        lockNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.authenticator = authenticator
        self.sleepClock = sleepClock
        self.lockNotificationCenter = lockNotificationCenter
        super.init()
        lockNotificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        lockNotificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
    }

    var isEnabled: Bool {
        state.isEnabled
    }

    var isLocked: Bool {
        state.isLocked
    }

    func configure(
        enabled: Bool,
        option: AutoLockOption,
        startsLocked: Bool = false
    ) {
        self.option = option
        if !enabled {
            state = .disabled
        } else if startsLocked {
            state = .locked
        } else if state == .disabled {
            state = .unlocked
        }
        scheduleInactivityLock()
    }

    func recordActivity() {
        guard state == .unlocked else { return }
        scheduleInactivityLock()
    }

    func lock() {
        guard state.isEnabled else { return }
        inactivityTask?.cancel()
        state = .locked
        errorMessage = nil
    }

    func unlock() async {
        guard state == .locked else { return }
        guard await authenticate(reason: String(localized: "Unlock Clipboard History")) else {
            return
        }
        state = .unlocked
        scheduleInactivityLock()
    }

    @discardableResult
    func authenticateAndSetEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != state.isEnabled else { return true }
        let reason = enabled
            ? String(localized: "Enable Clipboard History application lock")
            : String(localized: "Disable Clipboard History application lock")
        guard await authenticate(reason: reason) else { return false }
        state = enabled ? .unlocked : .disabled
        scheduleInactivityLock()
        return true
    }

    @discardableResult
    func authenticateSensitiveContentAccess() async -> Bool {
        await authenticate(
            reason: String(localized: "Authenticate to access this sensitive clipboard item")
        )
    }

    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let success = try await authenticator.authenticate(
                reason: reason
            )
            if success {
                errorMessage = nil
                return true
            }
            errorMessage = String(localized: "System authentication was cancelled.")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.lifecycle.error(
                "System authentication failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
        return false
    }

    @objc private func sessionDidResignActive() {
        if option == .whenMacLocks {
            lock()
        }
    }

    @objc private func screensDidSleep() {
        if option == .whenMacLocks {
            lock()
        }
    }

    private func scheduleInactivityLock() {
        inactivityTask?.cancel()
        guard state == .unlocked,
              let duration = option.inactivityDuration else { return }
        inactivityTask = Task { [weak self] in
            do {
                try await self?.sleepClock.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.lock()
            } catch {
                // Cancellation is expected whenever user activity resets the timer.
            }
        }
    }

    deinit {
        inactivityTask?.cancel()
        lockNotificationCenter.removeObserver(self)
    }
}
