import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ArchivePanelSelecting: AnyObject {
    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL?
    func openSource(allowedTypes: [UTType]) async -> URL?
}
