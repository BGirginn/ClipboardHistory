import CoreAudio
import AudioToolbox
import XCTest

@testable import ClipboardHistory

@MainActor
final class ProcessAudioEngineTests: XCTestCase {
    func testPipelineLifecycleAndCoreAudioFailuresUseDeterministicBackend() throws {
        let state = ProcessAudioPipelineDependencyState()
        var pipeline: ProcessAudioPipeline? = try ProcessAudioPipeline(
            processObjectIDs: [12, 11],
            gain: 0.4,
            dependencies: state.dependencies
        )
        XCTAssertTrue(pipeline?.usesCurrentOutputDevice() == true)
        state.outputDevice = 99
        XCTAssertFalse(pipeline?.usesCurrentOutputDevice() == true)
        pipeline?.setGain(0.7)
        pipeline?.stop()
        pipeline?.stop()
        XCTAssertEqual(state.stopCount, 1)
        XCTAssertEqual(state.destroyIOProcCount, 1)
        XCTAssertEqual(state.destroyedAggregateIDs, [22])
        XCTAssertEqual(state.destroyedTapIDs, [21])
        pipeline = nil

        try assertPipelineFailure(.outputDeviceUnavailable) {
            $0.outputStatus = -1
        }
        try assertPipelineFailure(.outputDeviceUnavailable) {
            $0.outputSize = 0
        }
        try assertPipelineFailure(.outputDeviceIdentifierUnavailable) {
            $0.uidStatus = -2
        }
        try assertPipelineFailure(.outputDeviceIdentifierUnavailable) {
            $0.uid = "" as CFString
        }
        try assertPipelineFailure(.tapCreationFailed(-3)) {
            $0.tapStatus = -3
        }
        try assertPipelineFailure(.aggregateDeviceCreationFailed(-4)) {
            $0.aggregateStatus = -4
        }
        try assertPipelineFailure(.unsupportedStreamFormat) {
            $0.formatStatus = -5
        }
        try assertPipelineFailure(.unsupportedStreamFormat) {
            $0.format.mBitsPerChannel = 16
        }
        try assertPipelineFailure(.ioProcedureCreationFailed(-6)) {
            $0.ioStatus = -6
        }
        try assertPipelineFailure(.ioProcedureCreationFailed(noErr)) {
            $0.ioProc = nil
        }
        try assertPipelineFailure(.deviceStartFailed(-7)) {
            $0.startStatus = -7
        }
    }

    func testLivePipelineDependencyReadsCurrentOutputMetadataWithoutMutation() {
        let dependencies = ProcessAudioPipelineDependencies.live
        let noOpIOProc: AudioDeviceIOProcID = { _, _, _, _, _, _, _ in noErr }
        _ = dependencies.startDevice(kAudioObjectUnknown, noOpIOProc)
        dependencies.stopDevice(kAudioObjectUnknown, noOpIOProc)
        dependencies.destroyIOProc(kAudioObjectUnknown, noOpIOProc)
        dependencies.destroyAggregateDevice(kAudioObjectUnknown)
        dependencies.destroyProcessTap(kAudioObjectUnknown)
        let (_, createdIOProc) = dependencies.createIOProc(
            kAudioObjectUnknown,
            { _, _ in }
        )
        if let createdIOProc {
            dependencies.destroyIOProc(kAudioObjectUnknown, createdIOProc)
        }
        let (_, aggregateID) = dependencies.createAggregateDevice([:] as CFDictionary)
        if aggregateID != kAudioObjectUnknown {
            dependencies.destroyAggregateDevice(aggregateID)
        }
        let (status, size, device) = dependencies.defaultOutputDevice()
        guard status == noErr,
              size == UInt32(MemoryLayout<AudioDeviceID>.size),
              device != kAudioObjectUnknown else { return }
        _ = dependencies.deviceUID(device)
        _ = dependencies.streamFormat(device)
    }

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

    private func assertPipelineFailure(
        _ expected: ProcessAudioEngineError,
        configure: (ProcessAudioPipelineDependencyState) -> Void
    ) throws {
        let state = ProcessAudioPipelineDependencyState()
        configure(state)
        XCTAssertThrowsError(
            try ProcessAudioPipeline(
                processObjectIDs: [11],
                gain: 1,
                dependencies: state.dependencies
            )
        ) { error in
            XCTAssertEqual(error as? ProcessAudioEngineError, expected)
        }
    }
}

private final class ProcessAudioPipelineDependencyState {
    var outputStatus = OSStatus(noErr)
    var outputSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var outputDevice = AudioDeviceID(20)
    var uidStatus = OSStatus(noErr)
    var uidSize = UInt32(MemoryLayout<CFString?>.size)
    var uid: CFString? = "test-output" as CFString
    var tapStatus = OSStatus(noErr)
    var aggregateStatus = OSStatus(noErr)
    var formatStatus = OSStatus(noErr)
    var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
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
    var ioStatus = OSStatus(noErr)
    var ioProc: AudioDeviceIOProcID? = { _, _, _, _, _, _, _ in noErr }
    var startStatus = OSStatus(noErr)
    private(set) var stopCount = 0
    private(set) var destroyIOProcCount = 0
    private(set) var destroyedAggregateIDs: [AudioObjectID] = []
    private(set) var destroyedTapIDs: [AudioObjectID] = []

    var dependencies: ProcessAudioPipelineDependencies {
        ProcessAudioPipelineDependencies(
            defaultOutputDevice: { [self] in
                (outputStatus, outputSize, outputDevice)
            },
            deviceUID: { [self] _ in (uidStatus, uidSize, uid) },
            createProcessTap: { [self] _ in (tapStatus, 21) },
            createAggregateDevice: { [self] _ in (aggregateStatus, 22) },
            streamFormat: { [self] _ in (formatStatus, formatSize, format) },
            createIOProc: { [self] _, _ in (ioStatus, ioProc) },
            startDevice: { [self] _, _ in startStatus },
            stopDevice: { [self] _, _ in stopCount += 1 },
            destroyIOProc: { [self] _, _ in destroyIOProcCount += 1 },
            destroyAggregateDevice: { [self] in destroyedAggregateIDs.append($0) },
            destroyProcessTap: { [self] in destroyedTapIDs.append($0) }
        )
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
