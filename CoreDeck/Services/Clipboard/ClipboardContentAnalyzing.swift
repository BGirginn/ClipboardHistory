import Foundation

protocol ClipboardContentAnalyzing: Sendable {
    func analyze(
        _ content: ClipboardContent,
        recognizesImageText: Bool
    ) async -> ClipboardContentAnalysis
}
