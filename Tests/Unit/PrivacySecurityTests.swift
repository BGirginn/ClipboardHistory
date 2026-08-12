import AppKit
import Carbon
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class PrivacySecurityTests: XCTestCase {
    func testSecretDetectorRecognizesHighConfidencePatterns() {
        let detector = SecretDetectionService()
        let privateKeyMarker = ["-----BEGIN", "OPENSSH", "PRIVATE", "KEY-----"].joined(separator: " ")
        let samples = [
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345",
            "github_token=" + "ghp" + "_abcdefghijklmnopqrstuvwxyz123456",
            "OPENAI_API_KEY=" + "sk" + "-abcdefghijklmnopqrstuvwxyz123456",
            "SLACK_TOKEN=" + "xoxb" + "-1234567890-abcdefghijklmnopqrstuvwxyz",
            "AWS_ACCESS_KEY_ID=" + "AKIA" + "IOSFODNN7EXAMPLE",
            privateKeyMarker + "\nabc\n" + privateKeyMarker.replacingOccurrences(of: "BEGIN", with: "END"),
            "-----BEGIN PRIVATE KEY-----\nYWJjZA==\n-----END PRIVATE KEY-----",
            "-----BEGIN ENCRYPTED PRIVATE KEY-----\nYWJjZA==\n-----END ENCRYPTED PRIVATE KEY-----",
            "postgres://admin:highentropysecret@localhost/database",
            "4111 1111 1111 1111",
            "Recovery codes:\nABCD-1234\nEFGH-5678"
        ]

        for sample in samples {
            XCTAssertTrue(detector.detect(in: sample, sourceBundleIdentifier: nil).isSensitive)
        }
    }

    func testSecretDetectorAvoidsOrdinaryTextFalsePositives() {
        let detector = SecretDetectionService()
        let samples = [
            "The meeting starts at 10 and ends at 11.",
            "https://developer.apple.com/documentation/swift",
            "This is a normal paragraph about password security.",
            "let greeting = \"hello world\""
        ]

        for sample in samples {
            XCTAssertFalse(detector.detect(in: sample, sourceBundleIdentifier: nil).isSensitive)
        }
    }

    func testPasswordManagerSourceAddsSensitivitySignal() {
        let result = SecretDetectionService().detect(
            in: "correct-horse-battery-staple-93847",
            sourceBundleIdentifier: "com.1password.1password"
        )
        XCTAssertTrue(result.signals.contains("password-manager-source"))
        XCTAssertTrue(result.isSensitive)
    }

    func testAESGCMRoundTripAndTamperDetection() throws {
        let service = EncryptionService.ephemeral()
        let plaintext = Data("private clipboard value".utf8)
        let encrypted = try service.encrypt(plaintext)

        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertEqual(try service.decrypt(encrypted), plaintext)

        var tampered = encrypted
        tampered[tampered.startIndex] ^= 0x01
        XCTAssertThrowsError(try service.decrypt(tampered))
        XCTAssertThrowsError(try EncryptionService(keyData: Data(count: 12)))
    }

    func testKeychainFailureDoesNotCreateFallbackKey() {
        enum ExpectedFailure: Error { case unavailable }

        XCTAssertThrowsError(
            try EncryptionService.live(keyLoader: { throw ExpectedFailure.unavailable })
        )
    }

    func testScreenLockNotificationAutomaticallyLocks() {
        let lockService = AppLockService()
        lockService.configure(enabled: true, option: .whenMacLocks)

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        XCTAssertTrue(lockService.isLocked)
    }

    func testGlobalShortcutRegistersAndDisablesWithoutError() {
        let monitor = GlobalShortcutMonitor(action: {})

        monitor.setEnabled(true)
        XCTAssertNil(monitor.registrationError)

        monitor.setEnabled(false)
        XCTAssertNil(monitor.registrationError)
    }

    @MainActor
    func testGlobalShortcutPressReleaseIsDebouncedAndMissingKeyUpCanBeCancelled() {
        var presses = 0
        var releases = 0
        let monitor = GlobalShortcutMonitor(
            action: { presses += 1 },
            releaseAction: { releases += 1 }
        )

        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyPressed))
        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyPressed))
        XCTAssertEqual(presses, 1)
        XCTAssertTrue(monitor.isPressed)
        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyReleased))
        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(releases, 1)
        monitor.handleHotKeyEvent(kind: UInt32.max)
        XCTAssertFalse(monitor.isPressed)

        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyPressed))
        monitor.cancelHeldShortcut()
        monitor.handleHotKeyEvent(kind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(releases, 1)
    }

    func testGlobalShortcutInjectedRegistrationFailuresAndDefaultReleaseAction() {
        let installFailure = StubGlobalShortcutBackend(installStatus: OSStatus(eventInternalErr))
        let failedInstall = GlobalShortcutMonitor(action: {}, backend: installFailure)
        failedInstall.setEnabled(true)
        XCTAssertNotNil(failedInstall.registrationError)

        let duplicateBackend = StubGlobalShortcutBackend(
            registerStatus: OSStatus(eventHotKeyExistsErr)
        )
        let duplicate = GlobalShortcutMonitor(action: {}, backend: duplicateBackend)
        duplicate.setEnabled(true)
        XCTAssertTrue(duplicate.registrationError?.contains(GlobalShortcut.defaultShortcut.title) == true)

        let genericBackend = StubGlobalShortcutBackend(registerStatus: OSStatus(eventInternalErr))
        let generic = GlobalShortcutMonitor(action: {}, backend: genericBackend)
        generic.setEnabled(true, shortcut: GlobalShortcut.defaultShortcut)
        XCTAssertNotNil(generic.registrationError)
        XCTAssertFalse(generic.registrationError?.contains(GlobalShortcut.defaultShortcut.title) == true)
        XCTAssertEqual(genericBackend.unregisterCount, 2)

        let successBackend = StubGlobalShortcutBackend()
        let defaultRelease = GlobalShortcutMonitor(action: {}, backend: successBackend)
        defaultRelease.setEnabled(true)
        successBackend.eventAction?(UInt32(kEventHotKeyPressed))
        successBackend.eventAction?(UInt32(kEventHotKeyReleased))
        XCTAssertNil(defaultRelease.registrationError)
        XCTAssertFalse(defaultRelease.isPressed)
    }

    func testSystemGlobalShortcutCarbonCallbackForwardsEventKind() throws {
        let backend = SystemGlobalShortcutBackend()
        var receivedKind: UInt32?
        backend.eventAction = { receivedKind = $0 }
        XCTAssertEqual(SystemGlobalShortcutBackend.carbonEventHandler(nil, nil, nil), noErr)

        var event: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            EventAttributes(kEventAttributeNone),
            &event
        )
        XCTAssertEqual(createStatus, noErr)
        let unwrappedEvent = try XCTUnwrap(event)
        defer { ReleaseEvent(unwrappedEvent) }
        let pointer = Unmanaged.passUnretained(backend).toOpaque()

        XCTAssertEqual(
            SystemGlobalShortcutBackend.carbonEventHandler(nil, unwrappedEvent, pointer),
            noErr
        )
        XCTAssertEqual(receivedKind, UInt32(kEventHotKeyPressed))
    }

    func testPasswordArchiveUsesAuthenticatedEncryption() throws {
        let plaintext = Data("archive content".utf8)
        let encrypted = try PasswordArchiveCrypto.encrypt(plaintext, password: "correct password")

        XCTAssertTrue(PasswordArchiveCrypto.isEncryptedArchive(encrypted))
        XCTAssertFalse(String(data: encrypted, encoding: .utf8)?.contains("archive content") ?? false)
        XCTAssertEqual(try PasswordArchiveCrypto.decrypt(encrypted, password: "correct password"), plaintext)
        XCTAssertThrowsError(try PasswordArchiveCrypto.decrypt(encrypted, password: "wrong password"))
    }

    func testLegacyEncryptedDatabaseItemMigratesToOpenStorage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "EncryptedDatabaseTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        let secret = "database plaintext must not be visible"
        await storage.upsert(
            ClipboardItem(
                type: .text,
                text: secret,
                hash: "encrypted-database",
                isSensitive: true,
                isEncrypted: true
            )
        )
        let loaded = await storage.loadHistory()
        let diskContents = try combinedDiskContents(in: directory)

        XCTAssertEqual(loaded.first?.text, secret)
        XCTAssertNotNil(diskContents.range(of: Data(secret.utf8)))
        XCTAssertFalse(try XCTUnwrap(loaded.first).isEncrypted)
        await storage.close()

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        let reopenedItems = await reopened.loadHistory()
        XCTAssertEqual(reopenedItems.first?.text, secret)
        await reopened.close()
        try? FileManager.default.removeItem(at: directory)
    }

    func testHTMLSanitizerRemovesExecutableAndRemoteContent() throws {
        let input = Data("""
        <div onclick="steal()">Safe</div><script>alert(1)</script>
        <img src="https://example.com/tracker.png"><a href="//remote.test">Link</a>
        """.utf8)
        let sanitizedData = try XCTUnwrap(HTMLSanitizer.sanitize(input))
        let sanitized = try XCTUnwrap(String(data: sanitizedData, encoding: .utf8))

        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("script"))
        XCTAssertFalse(sanitized.localizedCaseInsensitiveContains("onclick"))
        XCTAssertFalse(sanitized.contains("https://"))
        XCTAssertEqual(HTMLSanitizer.plainText(fromSanitizedHTML: sanitized), "Safe Link")
    }

    func testSettingsPersistence() {
        let suite = "PrivacySecurityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("all", forKey: "encryptionMode")
        let first = AppSettings(defaults: defaults)
        first.secretDetectionEnabled = false
        first.duplicateDetectionScope = .lastHour
        first.excludedBundleIdentifiersText = "com.example.private"

        let second = AppSettings(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "encryptionMode"))
        XCTAssertFalse(second.secretDetectionEnabled)
        XCTAssertEqual(second.duplicateDetectionScope, .lastHour)
        XCTAssertTrue(second.excludedBundleIdentifiers.contains("com.example.private"))
    }

    func testApplicationExclusionAndPrivateModeBlockCapture() async throws {
        let context = try makeViewModel()
        defer { cleanup(context) }
        context.settings.excludedBundleIdentifiersText = "com.example.private"

        XCTAssertFalse(context.viewModel.shouldCapture(from: "com.example.private"))
        XCTAssertTrue(context.viewModel.shouldCapture(from: "com.example.allowed"))
        context.viewModel.togglePrivateMode()
        await context.viewModel.insert(.text(value: "not recorded", hash: "private"))
        XCTAssertTrue(context.viewModel.items.isEmpty)
        await context.storage.close()
    }

    func testPrivateModeAndPauseControlsReplaceOlderTimers() async throws {
        let context = try makeViewModel()
        defer { cleanup(context) }

        context.viewModel.enablePrivateMode(minutes: 5)
        XCTAssertTrue(context.viewModel.isPrivateMode)
        XCTAssertNotNil(context.viewModel.privateModeUntil)
        XCTAssertNil(context.viewModel.pauseUntil)

        context.viewModel.pauseRecording(minutes: 15)
        XCTAssertFalse(context.viewModel.isPrivateMode)
        XCTAssertNil(context.viewModel.privateModeUntil)
        XCTAssertNotNil(context.viewModel.pauseUntil)

        context.viewModel.setPrivateModeEnabled(true)
        XCTAssertTrue(context.viewModel.isPrivateMode)
        XCTAssertNil(context.viewModel.privateModeUntil)
        XCTAssertNil(context.viewModel.pauseUntil)

        context.viewModel.resumeRecording()
        XCTAssertFalse(context.viewModel.isPrivateMode)
        XCTAssertNil(context.viewModel.privateModeUntil)
        XCTAssertNil(context.viewModel.pauseUntil)
        await context.storage.close()
    }

    func testSensitiveDefaultNeverTouchesDiskAndExpires() async throws {
        let context = try makeViewModel()
        defer { cleanup(context) }
        context.settings.sensitiveRetentionSeconds = 1
        let secret = "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345"

        await context.viewModel.insert(.text(value: secret, hash: HashUtility.sha256(text: secret)))

        XCTAssertEqual(context.viewModel.items.first?.isSensitive, true)
        let persisted = await context.storage.loadHistory()
        XCTAssertTrue(persisted.isEmpty)
        let diskContents = try combinedDiskContents(in: context.directory)
        XCTAssertNil(diskContents.range(of: Data(secret.utf8)))
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertTrue(context.viewModel.items.isEmpty)
        await context.storage.close()
    }

    func testManualLockHidesAndBlocksRestoration() async throws {
        let context = try makeViewModel()
        defer { cleanup(context) }
        await context.viewModel.insert(.text(value: "locked", hash: "locked"))
        let item = try XCTUnwrap(context.viewModel.items.first)
        context.viewModel.lockService.configure(enabled: true, option: .never)
        context.viewModel.lock()

        await context.viewModel.restoreAndWait(item)

        XCTAssertTrue(context.viewModel.isLocked)
        await context.storage.close()
    }

    private struct Context {
        let directory: URL
        let storage: StorageService
        let settings: AppSettings
        let viewModel: ClipboardHistoryViewModel
        let defaultsSuite: String
    }

    private func makeViewModel() throws -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PrivacySecurityTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suite = "PrivacySecurityDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let pasteboard = NSPasteboard(name: .init("PrivacySecurityPasteboard-\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: monitor,
            restorePasteboard: pasteboard,
            settings: settings,
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            storage: storage,
            settings: settings,
            viewModel: viewModel,
            defaultsSuite: suite
        )
    }

    private func cleanup(_ context: Context) {
        context.viewModel.prepareForShutdown()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func combinedDiskContents(in directory: URL) throws -> Data {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return Data()
        }
        var result = Data()
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            if let data = try? Data(contentsOf: url) { result.append(data) }
        }
        return result
    }
}

@MainActor
private final class StubGlobalShortcutBackend: GlobalShortcutBackend {
    var eventAction: ((UInt32) -> Void)?
    let installStatus: OSStatus
    let registerStatus: OSStatus
    private(set) var unregisterCount = 0

    init(installStatus: OSStatus = noErr, registerStatus: OSStatus = noErr) {
        self.installStatus = installStatus
        self.registerStatus = registerStatus
    }

    func installEventHandler() -> OSStatus {
        installStatus
    }

    func register(shortcut: GlobalShortcut) -> OSStatus {
        registerStatus
    }

    func unregister() {
        unregisterCount += 1
    }
}
