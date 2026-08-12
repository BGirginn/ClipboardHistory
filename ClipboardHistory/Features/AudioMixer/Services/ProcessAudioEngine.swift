import CoreAudio
import Foundation

@MainActor
final class ProcessAudioEngine: ProcessAudioControlling {
    typealias PipelineFactory = @MainActor (Set<AudioObjectID>, Double) throws -> any ProcessAudioPipelining

    private var pipelines: [String: any ProcessAudioPipelining] = [:]
    private var processIDs: [String: Set<AudioObjectID>] = [:]
    private var gains: [String: Double] = [:]
    private var failureHandler: (@MainActor @Sendable (String, Error) -> Void)?
    private let listenerQueue = DispatchQueue(label: "com.brgirgin.ClipboardHistory.audio-output")
    private let pipelineFactory: PipelineFactory
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?

    init(
        pipelineFactory: @escaping PipelineFactory = { processObjectIDs, gain in
            try ProcessAudioPipeline(processObjectIDs: processObjectIDs, gain: gain)
        }
    ) {
        self.pipelineFactory = pipelineFactory
        installOutputDeviceListener()
    }

    func setFailureHandler(_ handler: (@MainActor @Sendable (String, Error) -> Void)?) {
        failureHandler = handler
    }

    func setGain(_ gain: Double, for processObjectIDs: Set<AudioObjectID>, bundleID: String) throws {
        let normalizedGain = min(max(gain, 0), 1)
        if normalizedGain == 1 {
            stopControlling(bundleID: bundleID)
            return
        }
        if let pipeline = pipelines[bundleID],
           processIDs[bundleID] == processObjectIDs,
           pipeline.usesCurrentOutputDevice() {
            pipeline.setGain(normalizedGain)
            gains[bundleID] = normalizedGain
            return
        }
        let previousPipeline = pipelines[bundleID]
        do {
            let replacement = try pipelineFactory(processObjectIDs, normalizedGain)
            pipelines[bundleID] = replacement
            processIDs[bundleID] = processObjectIDs
            gains[bundleID] = normalizedGain
            previousPipeline?.stop()
        } catch {
            previousPipeline?.stop()
            pipelines.removeValue(forKey: bundleID)
            processIDs.removeValue(forKey: bundleID)
            gains.removeValue(forKey: bundleID)
            throw error
        }
    }

    func stopControlling(bundleID: String) {
        pipelines.removeValue(forKey: bundleID)?.stop()
        processIDs.removeValue(forKey: bundleID)
        gains.removeValue(forKey: bundleID)
    }

    func stopAll() {
        pipelines.values.forEach { $0.stop() }
        pipelines.removeAll()
        processIDs.removeAll()
        gains.removeAll()
        removeOutputDeviceListener()
    }

    private func installOutputDeviceListener() {
        var address = Self.defaultOutputAddress
        let relay = MainActorSignalRelay { [weak self] in
            self?.rebuildForOutputDeviceChange()
        }
        let listener = Self.outputListener(relay)
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            listener
        ) == noErr else { return }
        outputDeviceListener = listener
    }

    private func removeOutputDeviceListener() {
        guard let outputDeviceListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            outputDeviceListener
        )
        self.outputDeviceListener = nil
    }

    func rebuildForOutputDeviceChange() {
        let configurations = gains.compactMap { bundleID, gain -> (String, Double, Set<AudioObjectID>)? in
            guard let processObjectIDs = processIDs[bundleID] else { return nil }
            return (bundleID, gain, processObjectIDs)
        }
        for (bundleID, gain, processObjectIDs) in configurations {
            do {
                try setGain(gain, for: processObjectIDs, bundleID: bundleID)
            } catch {
                failureHandler?(bundleID, error)
            }
        }
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static func outputListener(
        _ relay: MainActorSignalRelay
    ) -> AudioObjectPropertyListenerBlock {
        { _, _ in relay.signal() }
    }
}
