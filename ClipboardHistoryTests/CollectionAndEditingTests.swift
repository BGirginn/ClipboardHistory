import Foundation
import XCTest

@testable import ClipboardHistory

final class CollectionAndEditingTests: XCTestCase {
    func testLocalTextTransformationsAreDeterministicAndTurkishAware() {
        let turkish = Locale(identifier: "tr_TR")
        XCTAssertEqual(TextTransformation.uppercase.apply(to: "içerik", locale: turkish), "İÇERİK")
        XCTAssertEqual(TextTransformation.lowercase.apply(to: "IĞDIR", locale: turkish), "ığdır")
        XCTAssertEqual(TextTransformation.titleCase.apply(to: "istanbul izmir", locale: turkish), "İstanbul İzmir")
        XCTAssertEqual(TextTransformation.trimWhitespace.apply(to: "  value\n"), "value")
    }

    func testCollectionNameIsEncryptedAndDeletionClearsMembership() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryCollections-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let encryption = EncryptionService.ephemeral()
        let storage = StorageService(baseDirectory: directory, encryptionService: encryption)
        let collection = ClipboardCollection(name: "Secret Project", sortOrder: 4)
        try await storage.upsertCollection(collection)
        let item = ClipboardItem(
            type: .text,
            text: "value",
            hash: "value",
            collectionID: collection.id
        )
        await storage.upsert(item)
        await storage.close()

        let databaseBytes = try Data(contentsOf: storage.databaseFile)
        XCTAssertNil(databaseBytes.range(of: Data(collection.name.utf8)))

        let reopened = StorageService(baseDirectory: directory, encryptionService: encryption)
        let loadedCollections = try await reopened.loadCollectionsThrowing()
        let loadedCollection = try XCTUnwrap(loadedCollections.first)
        XCTAssertEqual(loadedCollection.id, collection.id)
        XCTAssertEqual(loadedCollection.name, collection.name)
        XCTAssertEqual(loadedCollection.sortOrder, collection.sortOrder)
        XCTAssertEqual(
            loadedCollection.creationDate.timeIntervalSince1970,
            collection.creationDate.timeIntervalSince1970,
            accuracy: 0.000_001
        )
        try await reopened.deleteCollection(id: collection.id)
        let remainingCollections = try await reopened.loadCollectionsThrowing()
        let remainingHistory = try await reopened.loadHistoryThrowing()
        XCTAssertTrue(remainingCollections.isEmpty)
        XCTAssertNil(remainingHistory.first?.collectionID)
        await reopened.close()
    }

    @MainActor
    func testEditingTextTitleTagsAndSnippetUpdatesPresentation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardHistoryEditing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "CollectionAndEditingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = ClipboardHistoryViewModel(
            storage: StorageService(baseDirectory: directory),
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )
        await viewModel.insert(.text(
            value: "before",
            rtfData: nil,
            htmlData: nil,
            subtype: .plainText,
            hash: HashUtility.sha256(text: "before"),
            sourceBundleIdentifier: "com.example.editor"
        ))
        let original = try XCTUnwrap(viewModel.items.first)
        let collectionID = UUID()

        viewModel.updateItem(
            original,
            title: "  Useful name  ",
            editedText: "after  \n",
            tags: "Important, Turkish, important,  ",
            collectionID: collectionID,
            isSnippet: true
        )

        let updated = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(updated.displayTitle, "Useful name")
        XCTAssertEqual(updated.text, "after  \n")
        XCTAssertEqual(
            updated.hash,
            HashUtility.sha256(
                text: TextNormalizer.normalizedForHash("after  \n")
            )
        )
        XCTAssertEqual(updated.protectedMetadata.tags, ["Important", "Turkish"])
        XCTAssertEqual(updated.collectionID, collectionID)
        XCTAssertTrue(updated.isSnippet)
        XCTAssertTrue(updated.isPinned)
        await viewModel.shutdown()
    }
}
