import CoreAudio
import Foundation

@MainActor
final class ProcessAudioEngine: ProcessAudioControlling {
    private var pipelines: [String: ProcessAudioPipeline] = [:]
    private var processIDs: [String: AudioObjectID] = [:]

    func setGain(_ gain: Double, for processObjectID: AudioObjectID, bundleID: String) throws {
        let normalizedGain = min(max(gain, 0), 1)
        if normalizedGain == 1 {
            stopControlling(bundleID: bundleID)
            return
        }
        if let pipeline = pipelines[bundleID],
           processIDs[bundleID] == processObjectID,
           pipeline.usesCurrentOutputDevice() {
            pipeline.setGain(normalizedGain)
            return
        }
        stopControlling(bundleID: bundleID)
        let pipeline = try ProcessAudioPipeline(processObjectID: processObjectID, gain: normalizedGain)
        pipelines[bundleID] = pipeline
        processIDs[bundleID] = processObjectID
    }

    func stopControlling(bundleID: String) {
        pipelines.removeValue(forKey: bundleID)?.stop()
        processIDs.removeValue(forKey: bundleID)
    }

    func stopAll() {
        pipelines.values.forEach { $0.stop() }
        pipelines.removeAll()
        processIDs.removeAll()
    }
}
