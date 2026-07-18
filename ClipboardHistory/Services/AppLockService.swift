import AppKit
import Combine
import Foundation
import LocalAuthentication

@MainActor
final class AppLockService: NSObject, ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var errorMessage: String?

    private var option: AutoLockOption = .never
    private var inactivityTask: Task<Void, Never>?

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
    }

    func configure(option: AutoLockOption) {
        self.option = option
        scheduleInactivityLock()
    }

    func recordActivity() {
        guard !isLocked else { return }
        scheduleInactivityLock()
    }

    func lock() {
        inactivityTask?.cancel()
        isLocked = true
        errorMessage = nil
    }

    func unlock() async {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            errorMessage = evaluationError?.localizedDescription ?? "System authentication is unavailable."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Clipboard History"
            )
            if success {
                isLocked = false
                errorMessage = nil
                scheduleInactivityLock()
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLog.lifecycle.error(
                "Unlock failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
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
        guard let duration = option.inactivityDuration else { return }
        inactivityTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.lock()
            } catch {
                // Cancellation is expected whenever user activity resets the timer.
            }
        }
    }

    deinit {
        inactivityTask?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
