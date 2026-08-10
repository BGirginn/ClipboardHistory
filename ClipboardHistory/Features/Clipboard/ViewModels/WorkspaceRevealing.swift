import Foundation

@MainActor
protocol WorkspaceRevealing {
    func reveal(_ urls: [URL])
}
