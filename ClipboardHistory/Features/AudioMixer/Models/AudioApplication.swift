import CoreAudio
import Foundation

struct AudioApplication: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let processObjectIDs: Set<AudioObjectID>
    let processID: pid_t
    let bundleID: String
    let name: String
    let isProducingOutput: Bool
    var volume: Double
    var isMuted: Bool
    var controlState: AudioControlState

    init(
        id: AudioObjectID,
        processObjectIDs: Set<AudioObjectID>? = nil,
        processID: pid_t,
        bundleID: String,
        name: String,
        isProducingOutput: Bool,
        volume: Double,
        isMuted: Bool,
        controlState: AudioControlState
    ) {
        self.id = id
        self.processObjectIDs = processObjectIDs ?? [id]
        self.processID = processID
        self.bundleID = bundleID
        self.name = name
        self.isProducingOutput = isProducingOutput
        self.volume = volume
        self.isMuted = isMuted
        self.controlState = controlState
    }
}
