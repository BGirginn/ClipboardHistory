import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ArchiveSavePanelPresenting: AnyObject {
    var canCreateDirectories: Bool { get set }
    var nameFieldStringValue: String { get set }
    var allowedContentTypes: [UTType] { get set }
    var url: URL? { get }
    func begin() async -> NSApplication.ModalResponse
}

extension NSSavePanel: ArchiveSavePanelPresenting {}
