import Foundation

struct BrowserAudioTab: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let browser: String
    let title: String
    let canSetVolume: Bool
    var volume: Double
    var isMuted: Bool
}
