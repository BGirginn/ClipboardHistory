import AppKit
import CoreAudio
import XCTest
@testable import ClipboardHistoryTestHost

@MainActor
final class ReliabilityRegressionTests: XCTestCase {
    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "Reliability-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testFailedClearRestoreKeepsRecoveryCopyAndRecoversAfterRestart() async throws {
        let directory = root()
        let storage = StorageService(baseDirectory: directory, fileManager: FailedRestoreFileManager(), operationFailureInjector: { op in
            if case .executeSQL("DELETE FROM ClipboardItems") = op { throw CocoaError(.fileWriteUnknown) }
        })
        _ = try await storage.loadHistoryThrowing()
        let id = UUID()
        let stored = await storage.storeImage(Data("synthetic".utf8), id: id)
        let filename = try XCTUnwrap(stored)
        let item = ClipboardItem(id: id, type: .image, imageFilename: filename, hash: "rollback")
        try await storage.upsertThrowing(item)
        do {
            _ = try await storage.clearAll()
            XCTFail("Expected recovery failure")
        } catch DatabaseError.recoveryRequired { }
        let operations = try FileManager.default.contentsOfDirectory(at: storage.operationsDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(operations.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: operations[0].appending(path: "Images/\(filename)").path))
        do { try await storage.upsertThrowing(.init(type: .text, text: "blocked", hash: "blocked")); XCTFail("Must block writes") }
        catch DatabaseError.recoveryRequired { }
        await storage.close()
        let recovered = StorageService(baseDirectory: directory)
        let items = try await recovered.loadHistoryThrowing()
        XCTAssertEqual(items.map(\.id), [id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.imagesDirectory.appending(path: filename).path))
        await recovered.close()
    }

    func testQuotaSubtractsAlreadyScheduledRetentionRemovals() async throws {
        let storage = StorageService(baseDirectory: root())
        let items = (0..<3).map { ClipboardItem(type: .text, text: String(repeating: "x", count: 1000), creationDate: .now.addingTimeInterval(Double($0 - 3) * 60), hash: "quota-\($0)") }
        await storage.saveHistory(items)
        let cost1 = try await storage.reclaimableStorageCost(for: items[1])
        let cost2 = try await storage.reclaimableStorageCost(for: items[2])
        let report = await storage.cleanup(historyLimit: 2, retentionDays: 30, imageRetentionDays: 30, maximumStorageBytes: cost1 + cost2)
        XCTAssertEqual(report.removedItemCount, 1)
        let kept = try await storage.loadHistoryThrowing()
        XCTAssertEqual(Set(kept.map(\.id)), Set(items.suffix(2).map(\.id)))
        await storage.close()
    }

    func testNotesReadFailureDoesNotMaterializeImportAssets() async throws {
        let directory = root()
        let source = StorageService(baseDirectory: directory.appending(path: "source"))
        _ = try await source.loadHistoryThrowing()
        let id = UUID()
        let stored = await source.storeImage(Data("synthetic".utf8), id: id)
        let filename = try XCTUnwrap(stored)
        let item = ClipboardItem(id: id, type: .image, imageFilename: filename, hash: "import")
        let archive = directory.appending(path: "archive.json")
        let service = ExportImportService()
        try await service.exportArchive(items: [item], storage: source, to: archive, mode: .fullUnencrypted, includeImagesAndDocuments: true)
        let destination = StorageService(baseDirectory: directory.appending(path: "destination"), operationFailureInjector: { op in
            if case let .prepareSQL(sql) = op, sql.contains("FROM Notes") { throw CocoaError(.fileReadUnknown) }
        })
        do { _ = try await service.importArchive(from: archive, storage: destination, existingItems: []); XCTFail("Expected failure") }
        catch { }
        let files = try FileManager.default.contentsOfDirectory(atPath: destination.imagesDirectory.path)
        XCTAssertTrue(files.isEmpty)
        await source.close()
        await destination.close()
    }

    func testFailedHistoryLimitDeletionPreservesUIIdentityAndDatabase() async throws {
        let storage = StorageService(baseDirectory: root(), operationFailureInjector: { op in
            if case let .prepareSQL(sql) = op, sql == "DELETE FROM ClipboardItems WHERE id = ?" {
                throw CocoaError(.fileWriteNoPermission)
            }
        })
        let suite = "Reliability-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = 10
        let model = ClipboardHistoryViewModel(
            storage: storage, monitor: ClipboardMonitor(pasteboard: board), restorePasteboard: board,
            settings: settings, launchAtLoginService: LaunchAtLoginService(backend: ReliabilityLoginBackend()),
            startsAutomatically: false
        )
        let items = (0..<11).map { ClipboardItem(type: .text, text: "Synthetic", creationDate: .now.addingTimeInterval(Double($0)), hash: "item-\($0)") }
        for item in items { try await storage.upsertThrowing(item) }
        model.items = items
        model.pasteboardIdentityByItemID[items[0].id] = .init(changeCount: 42)
        await model.enforceUnpinnedHistoryLimit()
        XCTAssertEqual(model.items.count, 11)
        XCTAssertNotNil(model.pasteboardIdentityByItemID[items[0].id])
        XCTAssertNotNil(model.errorMessage)
        let persisted = try await storage.loadHistoryThrowing()
        XCTAssertEqual(persisted.count, 11)
        _ = await model.shutdown()
    }

    func testActivationWaitsForItsOwnBrowserSource() throws {
        let bridge = BrowserAudioBridge()
        func payload(_ source: String, _ id: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["version": 1, "type": "state", "source": source, "tabs": [["id": id, "browser": source, "title": "Synthetic", "canSetVolume": true, "volume": 100, "isMuted": false]]])
        }
        _ = bridge.handle(payload: try payload("safari", "safari:1"))
        _ = bridge.handle(payload: try payload("chromium:test", "chromium:test:2"))
        bridge.activate(tabID: "safari:1")
        let chrome = try XCTUnwrap(bridge.handle(payload: payload("chromium:test", "chromium:test:2")))
        let safari = try XCTUnwrap(bridge.handle(payload: payload("safari", "safari:1")))
        XCTAssertFalse(String(decoding: chrome, as: UTF8.self).contains("activate"))
        XCTAssertTrue(String(decoding: safari, as: UTF8.self).contains("activate"))
        let repeated = try XCTUnwrap(bridge.handle(payload: payload("safari", "safari:1")))
        XCTAssertFalse(String(decoding: repeated, as: UTF8.self).contains("activate"))
    }

    func testPrivateModePauseAndShutdownInvalidatePendingAnalysis() async throws {
        for boundary in ["private", "pause", "shutdown"] {
            let directory = root()
            let storage = StorageService(baseDirectory: directory)
            let analyzer = SuspendedCaptureAnalyzer()
            let suite = "Reliability-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let board = NSPasteboard(name: .init(suite))
            defer { board.releaseGlobally() }
            let model = ClipboardHistoryViewModel(
                storage: storage, monitor: ClipboardMonitor(pasteboard: board), restorePasteboard: board,
                settings: AppSettings(defaults: defaults), launchAtLoginService: LaunchAtLoginService(backend: ReliabilityLoginBackend()),
                contentAnalyzer: analyzer, startsAutomatically: false
            )
            await model.loadHistory()
            let task = Task { await model.insert(.text(value: "Synthetic", rtfData: nil, htmlData: nil, subtype: .plainText, hash: boundary, sourceBundleIdentifier: nil)) }
            while !(await analyzer.isWaiting) { await Task.yield() }
            switch boundary {
            case "private": model.setPrivateModeEnabled(true)
            case "pause": model.pauseRecording(minutes: 1)
            default: _ = await model.shutdown()
            }
            await analyzer.finish()
            await task.value
            XCTAssertTrue(model.items.isEmpty, boundary)
            _ = await model.shutdown()
            let restarted = StorageService(baseDirectory: directory)
            let persisted = try await restarted.loadHistoryThrowing()
            XCTAssertTrue(persisted.isEmpty, boundary)
            await restarted.close()
        }
    }

    func testClearInvalidatesCaptureAlreadyDeliveredToAnalyzer() async throws {
        let directory = root()
        let manager = IsolatedClearFileManager(root: directory.appending(path: "temp"))
        try manager.createDirectory(at: manager.temporaryDirectory, withIntermediateDirectories: true)
        let storage = StorageService(baseDirectory: directory.appending(path: "storage"), fileManager: manager)
        let analyzer = SuspendedCaptureAnalyzer()
        let suite = "Reliability-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let model = ClipboardHistoryViewModel(storage: storage, monitor: ClipboardMonitor(pasteboard: board), restorePasteboard: board, settings: AppSettings(defaults: defaults), launchAtLoginService: LaunchAtLoginService(backend: ReliabilityLoginBackend()), contentAnalyzer: analyzer, startsAutomatically: false)
        await model.loadHistory()
        let task = Task { await model.insert(.text(value: "Synthetic", rtfData: nil, htmlData: nil, subtype: .plainText, hash: "pending", sourceBundleIdentifier: nil)) }
        while !(await analyzer.isWaiting) { await Task.yield() }
        await model.clearHistoryNow()
        await analyzer.finish()
        await task.value
        let persisted = try await storage.loadHistoryThrowing()
        XCTAssertTrue(persisted.isEmpty)
        XCTAssertTrue(model.items.isEmpty)
        _ = await model.shutdown()
    }
}

private final class FailedRestoreFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at src: URL, to dst: URL) throws {
        if src.path.contains("/.operations/clear-"), src.lastPathComponent == "Images" { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: src, to: dst)
    }
}
private final class IsolatedClearFileManager: FileManager, @unchecked Sendable {
    let root: URL
    init(root: URL) { self.root = root; super.init() }
    override var temporaryDirectory: URL { root }
}
private actor SuspendedCaptureAnalyzer: ClipboardContentAnalyzing {
    var pending: CheckedContinuation<ClipboardContentAnalysis, Never>?
    var isWaiting: Bool { pending != nil }
    func analyze(_ content: ClipboardContent, recognizesImageText: Bool) async -> ClipboardContentAnalysis {
        await withCheckedContinuation { pending = $0 }
    }
    func finish() { pending?.resume(returning: .empty); pending = nil }
}
@MainActor private final class ReliabilityLoginBackend: LaunchAtLoginBackend {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws { }
}
