import CoreAudio
import Foundation

@MainActor
protocol ProcessAudioControlling: AnyObject {
    func setGain(_ gain: Double, for processObjectID: AudioObjectID, bundleID: String) throws
    func stopControlling(bundleID: String)
    func stopAll()
}
