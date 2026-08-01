import AppKit
import Foundation
import LocalAuthentication
import XCTest
@testable import ClipboardHistory

@MainActor
final class ApplicationLockTests: XCTestCase {
    func testLocalSystemAuthenticatorCoversSuccessCancellationAndUnavailableReasons() async throws {
        _ = LocalSystemAuthenticator()
        _ = LocalSystemAuthenticator.liveContext()
        let successContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: true,
            evaluationResult: .success(true)
        )
        let success = LocalSystemAuthenticator(contextProvider: { successContext })
        let didAuthenticate = try await success.authenticate(reason: "Unlock in test")
        XCTAssertTrue(didAuthenticate)
        XCTAssertEqual(successContext.reasons, ["Unlock in test"])
        XCTAssertEqual(
            successContext.policies,
            [.deviceOwnerAuthentication, .deviceOwnerAuthentication]
        )

        let cancellationContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: true,
            evaluationResult: .success(false)
        )
        let cancellation = LocalSystemAuthenticator(contextProvider: { cancellationContext })
        let didCancel = try await cancellation.authenticate(reason: "Cancel in test")
        XCTAssertFalse(didCancel)

        let explicitErrorContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: false,
            canEvaluateError: NSError(domain: LAError.errorDomain, code: LAError.biometryNotAvailable.rawValue),
            evaluationResult: .success(false)
        )
        let explicitError = LocalSystemAuthenticator(contextProvider: { explicitErrorContext })
        await XCTAssertThrowsErrorAsync(try await explicitError.authenticate(reason: "Unavailable")) {
            XCTAssertNotNil(($0 as? SystemAuthenticationError)?.errorDescription)
        }

        let fallbackContext = StubDeviceOwnerAuthenticationContext(
            canEvaluate: false,
            evaluationResult: .success(false)
        )
        let fallback = LocalSystemAuthenticator(contextProvider: { fallbackContext })
        await XCTAssertThrowsErrorAsync(try await fallback.authenticate(reason: "Unavailable")) {
            XCTAssertEqual(
                ($0 as? SystemAuthenticationError)?.errorDescription,
                "System authentication is unavailable."
            )
        }
    }

    func testDisabledStateIgnoresManualAndMacLockEvents() {
        let notifications = NotificationCenter()
        let authenticator = StubSystemAuthenticator { _ in true }
        let service = AppLockService(
            authenticator: authenticator,
            lockNotificationCenter: notifications
        )

        service.configure(enabled: false, option: .whenMacLocks)
        service.lock()
        notifications.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

        XCTAssertEqual(service.state, .disabled)
    }

    func testEnabledLaunchStartsLocked() {
        let service = AppLockService(authenticator: StubSystemAuthenticator { _ in true })

        service.configure(enabled: true, option: .whenMacLocks, startsLocked: true)

        XCTAssertEqual(service.state, .locked)
    }

    func testEnableUnlockAndDisableRequireSuccessfulAuthentication() async {
        let authenticator = StubSystemAuthenticator { _ in true }
        let service = AppLockService(authenticator: authenticator)

        let didEnable = await service.authenticateAndSetEnabled(true)
        XCTAssertTrue(didEnable)
        XCTAssertEqual(service.state, .unlocked)
        service.lock()
        XCTAssertEqual(service.state, .locked)
        await service.unlock()
        XCTAssertEqual(service.state, .unlocked)
        let didDisable = await service.authenticateAndSetEnabled(false)
        XCTAssertTrue(didDisable)
        XCTAssertEqual(service.state, .disabled)
        XCTAssertEqual(authenticator.reasons.count, 3)
    }

    func testCancelledAuthenticationLeavesStateUnchanged() async {
        let service = AppLockService(
            authenticator: StubSystemAuthenticator { _ in false }
        )

        let didEnable = await service.authenticateAndSetEnabled(true)
        XCTAssertFalse(didEnable)

        XCTAssertEqual(service.state, .disabled)
        XCTAssertNotNil(service.errorMessage)
    }

    func testCancelledUnlockAndActivityTimerResetStayFailClosed() async {
        let service = AppLockService(authenticator: StubSystemAuthenticator { _ in false })

        service.configure(enabled: true, option: .oneMinute, startsLocked: true)
        await service.unlock()
        XCTAssertEqual(service.state, .locked)

        let clock = CancellationCoverageSleepClock()
        let timerService = AppLockService(
            authenticator: StubSystemAuthenticator { _ in true },
            sleepClock: clock
        )
        timerService.configure(enabled: true, option: .oneMinute)
        await clock.waitForCallCount(1)
        timerService.recordActivity()
        await clock.waitForCallCount(2)
        timerService.configure(enabled: false, option: .never)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(timerService.state, .disabled)
        let cancellationCount = await clock.cancellationCount()
        XCTAssertGreaterThanOrEqual(cancellationCount, 1)
    }

    func testUnavailableAuthenticationLeavesStateUnchanged() async {
        let service = AppLockService(
            authenticator: StubSystemAuthenticator { _ in
                throw SystemAuthenticationError.unavailable("Unavailable in test")
            }
        )

        let didEnable = await service.authenticateAndSetEnabled(true)
        XCTAssertFalse(didEnable)

        XCTAssertEqual(service.state, .disabled)
        XCTAssertEqual(service.errorMessage, "Unavailable in test")
    }

    func testEveryInactivityOptionSchedulesItsExactDurationAndLocks() async {
        let expectations: [(AutoLockOption, Duration)] = [
            (.oneMinute, .seconds(60)),
            (.fiveMinutes, .seconds(300)),
            (.fifteenMinutes, .seconds(900))
        ]

        for (option, expectedDuration) in expectations {
            let clock = RecordingSleepClock()
            let service = AppLockService(
                authenticator: StubSystemAuthenticator { _ in true },
                sleepClock: clock
            )
            service.configure(enabled: true, option: option)
            await waitUntilLocked(service)

            XCTAssertEqual(service.state, .locked, "Failed option: \(option.rawValue)")
            let recordedDurations = await clock.recordedDurations()
            XCTAssertEqual(recordedDurations, [expectedDuration])
        }
    }

    func testNeverDoesNotScheduleAndMacLockUsesNotification() async {
        let notifications = NotificationCenter()
        let clock = RecordingSleepClock()
        let service = AppLockService(
            authenticator: StubSystemAuthenticator { _ in true },
            sleepClock: clock,
            lockNotificationCenter: notifications
        )

        service.configure(enabled: true, option: .never)
        await Task.yield()
        XCTAssertEqual(service.state, .unlocked)
        let recordedDurations = await clock.recordedDurations()
        XCTAssertTrue(recordedDurations.isEmpty)

        service.configure(enabled: true, option: .whenMacLocks)
        notifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertEqual(service.state, .locked)
    }

    func testSuccessfulEnableDefaultsToMacLockAndNextLaunchStartsLocked() async throws {
        let fixture = try makeFixture(authenticator: StubSystemAuthenticator { _ in true })
        defer { fixture.cleanup() }

        let didEnable = await fixture.viewModel.setApplicationLockEnabledAndWait(true)
        XCTAssertTrue(didEnable)
        XCTAssertTrue(fixture.settings.applicationLockEnabled)
        XCTAssertEqual(fixture.settings.autoLockOption, .whenMacLocks)
        XCTAssertEqual(fixture.viewModel.lockService.state, .unlocked)

        let reopenedSettings = AppSettings(defaults: fixture.defaults)
        let reopened = ClipboardHistoryViewModel(
            storage: fixture.storage,
            monitor: ClipboardMonitor(pasteboard: fixture.pasteboard),
            restorePasteboard: fixture.pasteboard,
            settings: reopenedSettings,
            lockService: AppLockService(authenticator: StubSystemAuthenticator { _ in true }),
            startsAutomatically: false
        )
        XCTAssertEqual(reopened.lockService.state, .locked)
        reopened.prepareForShutdown()
    }

    func testFailedEnableDoesNotChangePersistentSetting() async throws {
        let fixture = try makeFixture(authenticator: StubSystemAuthenticator { _ in false })
        defer { fixture.cleanup() }

        let didEnable = await fixture.viewModel.setApplicationLockEnabledAndWait(true)
        XCTAssertFalse(didEnable)
        XCTAssertFalse(fixture.settings.applicationLockEnabled)
        XCTAssertEqual(fixture.viewModel.lockService.state, .disabled)
    }

    func testLockedCapturePreferenceEncryptsOrDropsNewItems() async throws {
        let capturing = try makeFixture(
            authenticator: StubSystemAuthenticator { _ in true },
            lockEnabled: true,
            captureWhileLocked: true
        )
        defer { capturing.cleanup() }
        XCTAssertEqual(capturing.viewModel.lockService.state, .locked)

        await capturing.viewModel.insert(.text(value: "captured locked", hash: "locked-capture"))

        XCTAssertEqual(capturing.viewModel.items.count, 1)
        XCTAssertEqual(capturing.viewModel.items.first?.isEncrypted, true)
        let capturedHistory = await capturing.storage.loadHistory()
        XCTAssertEqual(capturedHistory.first?.isEncrypted, true)

        let dropping = try makeFixture(
            authenticator: StubSystemAuthenticator { _ in true },
            lockEnabled: true,
            captureWhileLocked: false
        )
        defer { dropping.cleanup() }

        await dropping.viewModel.insert(.text(value: "dropped locked", hash: "locked-drop"))
        await dropping.viewModel.lockService.unlock()

        XCTAssertTrue(dropping.viewModel.items.isEmpty)
        let droppedHistory = await dropping.storage.loadHistory()
        XCTAssertTrue(droppedHistory.isEmpty)
    }

    func testPrivateModeTakesPriorityOverLockedCapture() async throws {
        let fixture = try makeFixture(
            authenticator: StubSystemAuthenticator { _ in true },
            lockEnabled: true,
            captureWhileLocked: true
        )
        defer { fixture.cleanup() }
        fixture.viewModel.setPrivateModeEnabled(true)

        await fixture.viewModel.insert(.text(value: "private wins", hash: "private-wins"))

        XCTAssertTrue(fixture.viewModel.items.isEmpty)
    }

    func testSensitiveAskIsDeferredInMemoryUntilUnlock() async throws {
        let fixture = try makeFixture(
            authenticator: StubSystemAuthenticator { _ in true },
            lockEnabled: true,
            captureWhileLocked: true
        )
        defer { fixture.cleanup() }
        fixture.settings.sensitiveStoragePolicy = .ask
        let secret = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"

        await fixture.viewModel.insert(
            .text(value: secret, hash: HashUtility.sha256(text: secret))
        )

        XCTAssertEqual(fixture.viewModel.items.first?.isSensitive, true)
        XCTAssertFalse(fixture.viewModel.isShowingSensitiveSaveConfirmation)
        let persistedHistory = await fixture.storage.loadHistory()
        XCTAssertTrue(persistedHistory.isEmpty)

        await fixture.viewModel.unlockAndWait()

        XCTAssertEqual(fixture.viewModel.lockService.state, .unlocked)
        XCTAssertTrue(fixture.viewModel.isShowingSensitiveSaveConfirmation)
    }

    func testLockedRestoreAndPasteNeverWriteOrSendAccessibilityEvent() async throws {
        let pasteService = StubActiveApplicationPasteService()
        let fixture = try makeFixture(
            authenticator: StubSystemAuthenticator { _ in true },
            lockEnabled: true,
            captureWhileLocked: true,
            pasteService: pasteService
        )
        defer { fixture.cleanup() }
        await fixture.viewModel.insert(.text(value: "blocked interaction", hash: "blocked"))
        let item = try XCTUnwrap(fixture.viewModel.items.first)
        let initialChangeCount = fixture.pasteboard.changeCount

        await fixture.viewModel.restoreAndWait(item)
        await fixture.viewModel.pasteAndWait(item)

        XCTAssertEqual(fixture.pasteboard.changeCount, initialChangeCount)
        XCTAssertEqual(pasteService.pasteCount, 0)
    }

    private func waitUntilLocked(_ service: AppLockService) async {
        for _ in 0..<20 where service.state != .locked {
            await Task.yield()
        }
    }

    private func makeFixture(
        authenticator: StubSystemAuthenticator,
        lockEnabled: Bool = false,
        captureWhileLocked: Bool = true,
        pasteService: StubActiveApplicationPasteService = StubActiveApplicationPasteService()
    ) throws -> ApplicationLockFixture {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ApplicationLockTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suite = "ApplicationLockDefaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(1, forKey: "applicationLockMigrationVersion")
        defaults.set(lockEnabled, forKey: "applicationLockEnabled")
        defaults.set(captureWhileLocked, forKey: "captureWhileLocked")
        let settings = AppSettings(defaults: defaults)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(
            name: .init("ApplicationLockPasteboard-\(UUID().uuidString)")
        )
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            pasteService: pasteService,
            settings: settings,
            lockService: AppLockService(authenticator: authenticator),
            startsAutomatically: false
        )
        return ApplicationLockFixture(
            directory: directory,
            suite: suite,
            defaults: defaults,
            settings: settings,
            storage: storage,
            pasteboard: pasteboard,
            viewModel: viewModel
        )
    }
}

private actor CancellationCoverageSleepClock: SleepClock {
    private var calls = 0
    private var cancellations = 0

    func sleep(for duration: Duration) async throws {
        calls += 1
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            cancellations += 1
            throw error
        }
    }

    func waitForCallCount(_ expected: Int) async {
        while calls < expected {
            await Task.yield()
        }
    }

    func cancellationCount() -> Int {
        cancellations
    }
}

@MainActor
private final class StubDeviceOwnerAuthenticationContext: DeviceOwnerAuthenticationContext {
    let canEvaluate: Bool
    let canEvaluateError: NSError?
    let evaluationResult: Result<Bool, Error>
    private(set) var policies: [LAPolicy] = []
    private(set) var reasons: [String] = []

    init(
        canEvaluate: Bool,
        canEvaluateError: NSError? = nil,
        evaluationResult: Result<Bool, Error>
    ) {
        self.canEvaluate = canEvaluate
        self.canEvaluateError = canEvaluateError
        self.evaluationResult = evaluationResult
    }

    func canEvaluatePolicy(
        _ policy: LAPolicy,
        error: AutoreleasingUnsafeMutablePointer<NSError?>?
    ) -> Bool {
        policies.append(policy)
        error?.pointee = canEvaluateError
        return canEvaluate
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        policies.append(policy)
        reasons.append(localizedReason)
        return try evaluationResult.get()
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
