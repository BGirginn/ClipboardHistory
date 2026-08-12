import CoreAudio
import AudioToolbox
import XCTest

@testable import ClipboardHistory

@MainActor
final class ProcessAudioEngineTests: XCTestCase {
    func testPipelineDSPFormatAndGainHelpersAreDeterministic() {
        XCTAssertEqual(ProcessAudioPipeline.normalizedGain(-1), 0)
        XCTAssertEqual(ProcessAudioPipeline.normalizedGain(0.5), 0.5)
        XCTAssertEqual(ProcessAudioPipeline.normalizedGain(2), 1)

        var format = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        XCTAssertTrue(ProcessAudioPipeline.isSupportedStreamFormat(format))
        format.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        XCTAssertTrue(ProcessAudioPipeline.isSupportedStreamFormat(format))
        format.mFormatID = kAudioFormatMPEG4AAC
        XCTAssertFalse(ProcessAudioPipeline.isSupportedStreamFormat(format))
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = 0
        XCTAssertFalse(ProcessAudioPipeline.isSupportedStreamFormat(format))
        format.mFormatFlags = kAudioFormatFlagIsFloat
        format.mBitsPerChannel = 16
        XCTAssertFalse(ProcessAudioPipeline.isSupportedStreamFormat(format))
        format.mBitsPerChannel = 32
        format.mBytesPerFrame = 0
        XCTAssertFalse(ProcessAudioPipeline.isSupportedStreamFormat(format))

        var input: [Float] = [-2, -1, 0.5, 2]
        var output = Array(repeating: Float.zero, count: 3)
        input.withUnsafeMutableBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                var inputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(inputBytes.count),
                        mData: inputBytes.baseAddress
                    )
                )
                var outputList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(outputBytes.count),
                        mData: outputBytes.baseAddress
                    )
                )
                withUnsafePointer(to: &inputList) { inputPointer in
                    withUnsafeMutablePointer(to: &outputList) { outputPointer in
                        ProcessAudioPipeline.processBuffers(
                            inputData: inputPointer,
                            outputData: outputPointer,
                            gain: 0.5
                        )
                    }
                }
                XCTAssertEqual(outputList.mBuffers.mDataByteSize, UInt32(outputBytes.count))
            }
        }
        XCTAssertEqual(output, [-1, -0.5, 0.25])

        var emptyInput = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )
        var emptyOutput = emptyInput
        withUnsafePointer(to: &emptyInput) { inputPointer in
            withUnsafeMutablePointer(to: &emptyOutput) { outputPointer in
                ProcessAudioPipeline.processBuffers(
                    inputData: inputPointer,
                    outputData: outputPointer,
                    gain: 1
                )
            }
        }
    }

    func testPipelineReplacementReuseStopAndFailureAreFailOpen() throws {
        let state = ProcessAudioEngineFactoryState()
        let engine = ProcessAudioEngine { objectIDs, gain in
            if let nextError = state.error {
                throw nextError
            }
            let pipeline = ProcessAudioPipelineStub(objectIDs: objectIDs, gain: gain)
            state.created.append(pipeline)
            return pipeline
        }
        defer { engine.stopAll() }

        try engine.setGain(0.5, for: [11, 12], bundleID: "app.one")
        XCTAssertEqual(state.created.count, 1)
        XCTAssertEqual(state.created[0].gains, [0.5])

        try engine.setGain(0.25, for: [11, 12], bundleID: "app.one")
        XCTAssertEqual(state.created.count, 1)
        XCTAssertEqual(state.created[0].gains, [0.5, 0.25])

        state.created[0].usesCurrentDevice = false
        try engine.setGain(0.75, for: [11, 12], bundleID: "app.one")
        XCTAssertEqual(state.created.count, 2)
        XCTAssertEqual(state.created[0].stopCount, 1)

        state.error = ProcessAudioEngineError.unsupportedStreamFormat
        XCTAssertThrowsError(
            try engine.setGain(0.4, for: [99], bundleID: "app.one")
        )
        XCTAssertEqual(state.created[1].stopCount, 1)

        state.error = nil
        try engine.setGain(-1, for: [21], bundleID: "app.two")
        XCTAssertEqual(state.created.last?.gains, [0])
        try engine.setGain(2, for: [21], bundleID: "app.two")
        XCTAssertEqual(state.created.last?.stopCount, 1)
        engine.stopControlling(bundleID: "missing")
    }

    func testOutputDeviceRebuildReportsFailureAndStopAllIsIdempotent() throws {
        let state = ProcessAudioEngineFactoryState()
        var receivedFailure: (String, ProcessAudioEngineError)?
        let engine = ProcessAudioEngine { objectIDs, gain in
            if state.shouldFail { throw ProcessAudioEngineError.outputDeviceUnavailable }
            let pipeline = ProcessAudioPipelineStub(objectIDs: objectIDs, gain: gain)
            state.created.append(pipeline)
            return pipeline
        }
        engine.setFailureHandler { bundleID, error in
            receivedFailure = (bundleID, error as? ProcessAudioEngineError ?? .unsupportedStreamFormat)
        }

        try engine.setGain(0.4, for: [31], bundleID: "app.rebuild")
        state.created[0].usesCurrentDevice = false
        state.shouldFail = true
        engine.rebuildForOutputDeviceChange()
        XCTAssertEqual(receivedFailure?.0, "app.rebuild")
        XCTAssertEqual(receivedFailure?.1, .outputDeviceUnavailable)
        XCTAssertEqual(state.created[0].stopCount, 1)

        engine.setFailureHandler(nil)
        engine.rebuildForOutputDeviceChange()
        engine.stopAll()
        engine.stopAll()
    }
}

@MainActor
private final class ProcessAudioPipelineStub: ProcessAudioPipelining {
    let objectIDs: Set<AudioObjectID>
    private(set) var gains: [Double]
    private(set) var stopCount = 0
    var usesCurrentDevice = true

    init(objectIDs: Set<AudioObjectID>, gain: Double) {
        self.objectIDs = objectIDs
        gains = [gain]
    }

    func setGain(_ gain: Double) {
        gains.append(gain)
    }

    func usesCurrentOutputDevice() -> Bool {
        usesCurrentDevice
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class ProcessAudioEngineFactoryState {
    var created: [ProcessAudioPipelineStub] = []
    var error: Error?
    var shouldFail = false
}
