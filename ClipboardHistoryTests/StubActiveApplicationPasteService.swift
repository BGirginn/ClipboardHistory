import Foundation

@testable import ClipboardHistory

@MainActor
final class StubActiveApplicationPasteService: ActiveApplicationPasting, @unchecked Sendable {
    var result: ActiveApplicationPasteResult
    private(set) var captureCount = 0
    private(set) var pasteCount = 0

    init(result: ActiveApplicationPasteResult = .pasted) {
        self.result = result
    }

    func captureTargetApplication() {
        captureCount += 1
    }

    func paste() async -> ActiveApplicationPasteResult {
        pasteCount += 1
        return result
    }
}
