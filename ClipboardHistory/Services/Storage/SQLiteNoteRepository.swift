import Foundation
import SQLite3

extension StorageService {
    func loadNotesThrowing() throws -> [Note] {
        try ensureInitialized()
        let statement = try prepare("""
            SELECT id, protectedTitle, protectedBody, createdAt, updatedAt
            FROM Notes
            ORDER BY updatedAt DESC
            """)
        defer { sqlite3_finalize(statement) }
        var notes: [Note] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = textColumn(0, statement),
                  let id = UUID(uuidString: idText),
                  let protectedTitle = dataColumn(1, statement),
                  let protectedBody = dataColumn(2, statement) else {
                throw DatabaseError.executionFailed("invalid note record")
            }
            let titleData = try noteEncryptionService().decrypt(protectedTitle)
            let bodyData = try noteEncryptionService().decrypt(protectedBody)
            guard let title = String(data: titleData, encoding: .utf8),
                  let body = String(data: bodyData, encoding: .utf8) else {
                throw DatabaseError.executionFailed("invalid note encoding")
            }
            notes.append(
                Note(
                    id: id,
                    title: title.isEmpty ? nil : title,
                    body: body,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
            )
        }
        return notes
    }

    func upsertNoteThrowing(_ note: Note) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try insertOrReplace(note)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func upsertNotesBatchThrowing(_ notes: [Note]) throws {
        try ensureInitialized()
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for note in notes {
                try insertOrReplace(note)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteNoteThrowing(id: UUID) throws {
        try ensureInitialized()
        let statement = try prepare("DELETE FROM Notes WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }

    func insertOrReplace(_ note: Note) throws {
        guard (note.title?.count ?? 0) <= Note.maximumTitleLength,
              Data(note.body.utf8).count <= Note.maximumBodyBytes else {
            throw DatabaseError.executionFailed("note size limit exceeded")
        }
        let protectedTitle = try noteEncryptionService().encrypt(Data((note.title ?? "").utf8))
        let protectedBody = try noteEncryptionService().encrypt(Data(note.body.utf8))
        let statement = try prepare("""
            INSERT OR REPLACE INTO Notes(id, protectedTitle, protectedBody, createdAt, updatedAt)
            VALUES (?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bind(note.id.uuidString, at: 1, to: statement)
        try bind(protectedTitle, at: 2, to: statement)
        try bind(protectedBody, at: 3, to: statement)
        sqlite3_bind_double(statement, 4, note.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 5, note.updatedAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(databaseMessage())
        }
    }
}
