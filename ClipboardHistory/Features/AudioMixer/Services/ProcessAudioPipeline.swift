import CoreAudio
import AudioToolbox
import Foundation
import libkern

final class ProcessAudioPipeline: @unchecked Sendable {
    private var gainBits = Int32(bitPattern: Float(1).bitPattern)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false
    private var routedOutputDevice = AudioDeviceID(kAudioObjectUnknown)

    init(processObjectIDs: Set<AudioObjectID>, gain: Double) throws {
        storeGain(gain)
        do {
            try start(processObjectIDs: processObjectIDs)
        } catch {
            stop()
            throw error
        }
    }

    deinit {
        stop()
    }

    func setGain(_ gain: Double) {
        storeGain(gain)
    }

    func usesCurrentOutputDevice() -> Bool {
        (try? defaultOutputDevice()) == routedOutputDevice
    }

    func stop() {
        if isRunning, let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
        }
        isRunning = false
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        self.ioProcID = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        routedOutputDevice = kAudioObjectUnknown
    }

    private func start(processObjectIDs: Set<AudioObjectID>) throws {
        let outputDevice = try defaultOutputDevice()
        routedOutputDevice = outputDevice
        let outputUID = try deviceUID(outputDevice)
        let tapDescription = CATapDescription(
            processes: processObjectIDs.sorted(),
            deviceUID: outputUID,
            stream: 0
        )
        tapDescription.name = "ClipboardHistory Audio Mixer"
        tapDescription.isPrivate = true
        tapDescription.isExclusive = false
        tapDescription.muteBehavior = .mutedWhenTapped

        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr else { throw ProcessAudioEngineError.tapCreationFailed(tapStatus) }

        let aggregateUID = "com.brgirgin.ClipboardHistory.AudioMixer.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ClipboardHistory Audio Mixer",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]],
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceIsPrivateKey: true
        ]
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &aggregateDeviceID
        )
        guard aggregateStatus == noErr else {
            throw ProcessAudioEngineError.aggregateDeviceCreationFailed(aggregateStatus)
        }
        try validateStreamFormat(of: aggregateDeviceID)

        var createdIOProc: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProc,
            aggregateDeviceID,
            nil
        ) { [weak self] _, inputData, _, outputData, _ in
            guard let self else { return }
            process(inputData: inputData, outputData: outputData)
        }
        guard ioStatus == noErr, let createdIOProc else {
            throw ProcessAudioEngineError.ioProcedureCreationFailed(ioStatus)
        }
        ioProcID = createdIOProc
        let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProc)
        guard startStatus == noErr else { throw ProcessAudioEngineError.deviceStartFailed(startStatus) }
        isRunning = true
    }

    private func process(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>
    ) {
        let gain = Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &gainBits)))
        Self.processBuffers(inputData: inputData, outputData: outputData, gain: gain)
    }

    static func processBuffers(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
        for index in outputBuffers.indices {
            guard index < inputBuffers.count,
                  let inputPointer = inputBuffers[index].mData,
                  let outputPointer = outputBuffers[index].mData else { continue }
            let byteCount = min(
                Int(inputBuffers[index].mDataByteSize),
                Int(outputBuffers[index].mDataByteSize)
            )
            let sampleCount = byteCount / MemoryLayout<Float>.size
            let inputSamples = inputPointer.assumingMemoryBound(to: Float.self)
            let outputSamples = outputPointer.assumingMemoryBound(to: Float.self)
            AudioGainProcessor.apply(
                input: inputSamples,
                output: outputSamples,
                sampleCount: sampleCount,
                gain: gain
            )
            outputBuffers[index].mDataByteSize = UInt32(byteCount)
        }
    }

    private func storeGain(_ gain: Double) {
        let newValue = Int32(bitPattern: Self.normalizedGain(gain).bitPattern)
        while true {
            let oldValue = OSAtomicAdd32Barrier(0, &gainBits)
            if OSAtomicCompareAndSwap32Barrier(oldValue, newValue, &gainBits) { return }
        }
    }

    static func normalizedGain(_ gain: Double) -> Float {
        Float(min(max(gain, 0), 1))
    }

    private func validateStreamFormat(of device: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        let expectedSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var returnedSize = expectedSize
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &returnedSize,
            &format
        )
        guard status == noErr,
              returnedSize == expectedSize,
              Self.isSupportedStreamFormat(format) else {
            throw ProcessAudioEngineError.unsupportedStreamFormat
        }
    }

    static func isSupportedStreamFormat(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
            && format.mBytesPerFrame > 0
    }

    private func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr,
              size == UInt32(MemoryLayout<AudioDeviceID>.size),
              device != kAudioObjectUnknown else {
            throw ProcessAudioEngineError.outputDeviceUnavailable
        }
        return device
    }

    private func deviceUID(_ device: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        let expectedSize = UInt32(MemoryLayout<CFString?>.size)
        var size = expectedSize
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr,
              size == expectedSize,
              let uid,
              !String(uid).isEmpty else {
            throw ProcessAudioEngineError.outputDeviceIdentifierUnavailable
        }
        return uid as String
    }
}
