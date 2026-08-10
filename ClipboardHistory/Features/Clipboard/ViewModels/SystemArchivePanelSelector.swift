import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SystemArchivePanelSelector: ArchivePanelSelecting {
    private let makeSavePanel: @MainActor () -> any ArchiveSavePanelPresenting
    private let makeOpenPanel: @MainActor () -> any ArchiveOpenPanelPresenting

    init(
        makeSavePanel: (@MainActor () -> any ArchiveSavePanelPresenting)? = nil,
        makeOpenPanel: (@MainActor () -> any ArchiveOpenPanelPresenting)? = nil
    ) {
        self.makeSavePanel = makeSavePanel ?? NSSavePanel.init
        self.makeOpenPanel = makeOpenPanel ?? NSOpenPanel.init
    }

    func saveDestination(suggestedName: String, allowedTypes: [UTType]) async -> URL? {
        let panel = makeSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = allowedTypes
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }

    func openSource(allowedTypes: [UTType]) async -> URL? {
        let panel = makeOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
}
