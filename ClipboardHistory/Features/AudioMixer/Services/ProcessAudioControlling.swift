import CoreAudio
import Foundation

@MainActor
protocol ProcessAudioControlling: AnyObject {
    func setFailureHandler(_ handler: (@MainActor @Sendable (String, Error) -> Void)?)
    func setGain(_ gain: Double, for processObjectIDs: Set<AudioObjectID>, bundleID: String) throws
    func stopControlling(bundleID: String)
    func stopAll()
}

extension ProcessAudioControlling {
    func setFailureHandler(_ handler: (@MainActor @Sendable (String, Error) -> Void)?) {}
}
