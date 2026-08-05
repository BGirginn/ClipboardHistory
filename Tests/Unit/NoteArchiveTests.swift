import Foundation
import XCTest
@testable import ClipboardHistory

final class NoteArchiveTests: XCTestCase {
    func testV3FullRoundTripAndMetadataExclusion() async throws {
        let context = makeContext("NoteArchiveRoundTrip")
        let note = Note(
            title: nil,
            body: "Generated archive title\nPrivate body",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let fullURL = context.root.appending(path: "full.clipboardarchive")
        let metadataURL = context.root.appending(path: "metadata.clipboardarchive")

        try await context.service.exportArchive(
            items: [],
            storage: context.source,
            to: fullURL,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: false,
            notes: [note]
        )
        try await context.service.exportArchive(
            items: [],
            storage: context.source,
            to: metadataURL,
            mode: .metadataOnly,
            includeImagesAndDocuments: false,
            notes: [note]
        )

        let full = try decodeArchive(fullURL)
        let metadata = try decodeArchive(metadataURL)
        XCTAssertEqual(full.version, 3)
        XCTAssertEqual(full.notes, [note])
        XCTAssertEqual(full.noteHashes.count, 1)
        XCTAssertEqual(metadata.notes, [])
        XCTAssertEqual(metadata.noteHashes, [:])

        let report = try await context.service.importArchive(
            from: fullURL,
            storage: context.destination,
            existingItems: [],
            encryptionMode: .all
        )
        let imported = try await context.destination.loadNotesThrowing()
        XCTAssertEqual(report.importedNoteCount, 1)
        XCTAssertEqual(imported, [note])
    }

    func testV1AndV2TreatNotesAsEmpty() throws {
        let note = Note(title: "Must be ignored", body: "Legacy versions have no notes")
        for version in [1, 2] {
            let encoded = try JSONEncoder().encode(
                ClipboardArchive(
                    version: version,
                    createdAt: .now,
                    mode: .fullUnencrypted,
                    items: [],
                    assets: [:],
                    notes: [note],
                    noteHashes: [note.id.uuidString.lowercased(): "untrusted"]
                )
            )
            let decoded = try JSONDecoder().decode(ClipboardArchive.self, from: encoded)
            XCTAssertEqual(decoded.notes, [])
            XCTAssertEqual(decoded.noteHashes, [:])
        }
    }

    func testV3RejectsCorruptedNoteHash() async throws {
        let context = makeContext("NoteArchiveHash")
        let note = Note(title: "Hash", body: "Authenticated note")
        let archiveURL = context.root.appending(path: "archive.clipboardarchive")
        try await context.service.exportArchive(
            items: [],
            storage: context.source,
            to: archiveURL,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: false,
            notes: [note]
        )
        let archive = try decodeArchive(archiveURL)
        let corrupted = ClipboardArchive(
            version: archive.version,
            createdAt: archive.createdAt,
            mode: archive.mode,
            items: archive.items,
            assets: archive.assets,
            collections: archive.collections,
            notes: archive.notes,
            itemHashes: archive.itemHashes,
            assetHashes: archive.assetHashes,
            collectionHashes: archive.collectionHashes,
            noteHashes: [note.id.uuidString.lowercased(): "corrupted"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(corrupted).write(to: archiveURL, options: .atomic)

        do {
            _ = try await context.service.importArchive(
                from: archiveURL,
                storage: context.destination,
                existingItems: [],
                encryptionMode: .all
            )
            XCTFail("Expected note hash validation to fail")
        } catch ExportImportError.invalidArchive {
            let notes = try await context.destination.loadNotesThrowing()
            XCTAssertEqual(notes, [])
        }
    }

    func testDuplicateContentAndUUIDCollisionDoNotOverwrite() async throws {
        let context = makeContext("NoteArchiveDuplicates")
        let collisionID = UUID()
        let existingDuplicate = Note(title: "Duplicate", body: "Same content")
        let existingCollision = Note(id: collisionID, title: "Existing", body: "Keep me")
        try await context.destination.upsertNotesBatchThrowing([existingDuplicate, existingCollision])
        let duplicate = Note(title: "Duplicate", body: "Same content")
        let collision = Note(id: collisionID, title: "Imported", body: "New content")
        let archiveURL = context.root.appending(path: "duplicates.clipboardarchive")
        try await context.service.exportArchive(
            items: [],
            storage: context.source,
            to: archiveURL,
            mode: .fullUnencrypted,
            includeImagesAndDocuments: false,
            notes: [duplicate, collision]
        )

        let report = try await context.service.importArchive(
            from: archiveURL,
            storage: context.destination,
            existingItems: [],
            encryptionMode: .all
        )
        let notes = try await context.destination.loadNotesThrowing()

        XCTAssertEqual(report.importedNoteCount, 1)
        XCTAssertEqual(report.duplicateNoteCount, 1)
        XCTAssertEqual(notes.count, 3)
        XCTAssertEqual(notes.first(where: { $0.id == collisionID })?.body, "Keep me")
        XCTAssertNotEqual(notes.first(where: { $0.body == "New content" })?.id, collisionID)
    }

    private func makeContext(_ prefix: String) -> Context {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "\(prefix)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let context = Context(
            root: root,
            source: StorageService(baseDirectory: root.appending(path: "Source")),
            destination: StorageService(baseDirectory: root.appending(path: "Destination")),
            service: ExportImportService()
        )
        addTeardownBlock {
            await context.source.close()
            await context.destination.close()
            try? FileManager.default.removeItem(at: root)
        }
        return context
    }

    private func decodeArchive(_ url: URL) throws -> ClipboardArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(ClipboardArchive.self, from: Data(contentsOf: url))
    }

    private struct Context {
        let root: URL
        let source: StorageService
        let destination: StorageService
        let service: ExportImportService
    }
}
