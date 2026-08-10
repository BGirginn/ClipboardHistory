import CoreAudio
import Foundation

struct AudioApplication: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let processID: pid_t
    let bundleID: String
    let name: String
    let isProducingOutput: Bool
    var volume: Double
    var isMuted: Bool
    var controlState: AudioControlState
}
