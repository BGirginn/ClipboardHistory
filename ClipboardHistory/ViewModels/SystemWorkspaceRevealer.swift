import AppKit
import Foundation

@MainActor
struct SystemWorkspaceRevealer: WorkspaceRevealing {
    private let revealAction: ([URL]) -> Void

    init(
        revealAction: @escaping ([URL]) -> Void = NSWorkspace.shared.activateFileViewerSelecting
    ) {
        self.revealAction = revealAction
    }

    func reveal(_ urls: [URL]) {
        revealAction(urls)
    }
}
