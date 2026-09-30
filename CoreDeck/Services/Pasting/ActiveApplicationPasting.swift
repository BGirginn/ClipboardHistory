import Foundation

@MainActor
protocol ActiveApplicationPasting: Sendable {
    func captureTargetApplication()
    func paste() async -> ActiveApplicationPasteResult
}
