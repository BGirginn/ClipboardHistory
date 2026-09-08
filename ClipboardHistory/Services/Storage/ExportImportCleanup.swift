import Foundation

extension ExportImportService {
    func removeMaterializedAssets(_ items: [ClipboardItem], storage: StorageService) async throws {
        var failed = false
        for item in items {
            do { try await storage.deleteAssociatedFilesThrowing(for: item) }
            catch { failed = true }
        }
        guard !failed else { throw ExportImportError.cleanupFailed }
    }
}
