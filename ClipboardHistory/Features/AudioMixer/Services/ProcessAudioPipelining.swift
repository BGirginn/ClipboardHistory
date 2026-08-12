import CoreAudio
import Foundation

@MainActor
protocol ProcessAudioPipelining: AnyObject {
    func setGain(_ gain: Double)
    func usesCurrentOutputDevice() -> Bool
    func stop()
}

extension ProcessAudioPipeline: ProcessAudioPipelining {}
