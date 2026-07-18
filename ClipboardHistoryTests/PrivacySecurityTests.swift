import AppKit
import Foundation
import XCTest
@testable import ClipboardHistory

@MainActor
final class PrivacySecurityTests: XCTestCase {
    func testSecretDetectorRecognizesHighConfidencePatterns() {
        let detector = SecretDetectionService()
        let samples = [
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345",
            "github_token=ghp_abcdefghijklmnopqrstuvwxyz123456",
            "OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz123456",
            "SLACK_TOKEN=xoxb-1234567890-abcdefghijklmnopqrstuvwxyz",
            "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----",
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
        lockService.configure(option: .whenMacLocks)

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

    func testPasswordArchiveUsesAuthenticatedEncryption() throws {
        let plaintext = Data("archive content".utf8)
        let encrypted = try PasswordArchiveCrypto.encrypt(plaintext, password: "correct password")

        XCTAssertTrue(PasswordArchiveCrypto.isEncryptedArchive(encrypted))
        XCTAssertFalse(String(data: encrypted, encoding: .utf8)?.contains("archive content") ?? false)
        XCTAssertEqual(try PasswordArchiveCrypto.decrypt(encrypted, password: "correct password"), plaintext)
        XCTAssertThrowsError(try PasswordArchiveCrypto.decrypt(encrypted, password: "wrong password"))
    }

    func testEncryptedDatabaseTextIsNotReadableAtRest() async throws {
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
        XCTAssertNil(diskContents.range(of: Data(secret.utf8)))
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
        let first = AppSettings(defaults: defaults)
        first.encryptionMode = .all
        first.secretDetectionEnabled = false
        first.duplicateDetectionScope = .lastHour
        first.excludedBundleIdentifiersText = "com.example.private"

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.encryptionMode, .all)
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
