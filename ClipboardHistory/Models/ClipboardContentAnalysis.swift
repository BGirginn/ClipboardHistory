import Foundation

struct ClipboardContentAnalysis: Equatable, Sendable {
    var extractedText: String?
    var qrCodeText: String?
    var colorHex: String?

    static let empty = ClipboardContentAnalysis()
}
