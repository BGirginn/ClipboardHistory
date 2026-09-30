import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ArchiveOpenPanelPresenting: AnyObject {
    var canChooseDirectories: Bool { get set }
    var allowsMultipleSelection: Bool { get set }
    var allowedContentTypes: [UTType] { get set }
    var url: URL? { get }
    func begin() async -> NSApplication.ModalResponse
}

extension NSOpenPanel: ArchiveOpenPanelPresenting {}
