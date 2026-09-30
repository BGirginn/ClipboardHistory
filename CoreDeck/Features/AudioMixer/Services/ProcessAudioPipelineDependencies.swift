import AudioToolbox
import CoreAudio
import Foundation

struct ProcessAudioPipelineDependencies: @unchecked Sendable {
    var defaultOutputDevice: () -> (OSStatus, UInt32, AudioDeviceID)
    var deviceUID: (AudioDeviceID) -> (OSStatus, UInt32, CFString?)
    var createProcessTap: (CATapDescription) -> (OSStatus, AudioObjectID)
    var createAggregateDevice: (CFDictionary) -> (OSStatus, AudioObjectID)
    var streamFormat: (AudioDeviceID) -> (
        OSStatus,
        UInt32,
        AudioStreamBasicDescription
    )
    var createIOProc: (
        AudioDeviceID,
        @escaping (
            UnsafePointer<AudioBufferList>,
            UnsafeMutablePointer<AudioBufferList>
        ) -> Void
    ) -> (OSStatus, AudioDeviceIOProcID?)
    var startDevice: (AudioDeviceID, AudioDeviceIOProcID) -> OSStatus
    var stopDevice: (AudioDeviceID, AudioDeviceIOProcID) -> Void
    var destroyIOProc: (AudioDeviceID, AudioDeviceIOProcID) -> Void
    var destroyAggregateDevice: (AudioObjectID) -> Void
    var destroyProcessTap: (AudioObjectID) -> Void

    static let live = ProcessAudioPipelineDependencies(
        defaultOutputDevice: {
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
            return (status, size, device)
        },
        deviceUID: { device in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString?
            var size = UInt32(MemoryLayout<CFString?>.size)
            let status = withUnsafeMutablePointer(to: &uid) { pointer in
                AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
            }
            return (status, size, uid)
        },
        createProcessTap: { description in
            var identifier = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &identifier)
            return (status, identifier)
        },
        createAggregateDevice: { description in
            var identifier = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateAggregateDevice(description, &identifier)
            return (status, identifier)
        },
        streamFormat: { device in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let status = AudioObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                &size,
                &format
            )
            return (status, size, format)
        },
        createIOProc: { device, process in
            var createdIOProc: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(
                &createdIOProc,
                device,
                nil
            ) { _, inputData, _, outputData, _ in
                process(inputData, outputData)
            }
            return (status, createdIOProc)
        },
        startDevice: AudioDeviceStart,
        stopDevice: { device, ioProc in
            AudioDeviceStop(device, ioProc)
        },
        destroyIOProc: { device, ioProc in
            AudioDeviceDestroyIOProcID(device, ioProc)
        },
        destroyAggregateDevice: { identifier in
            AudioHardwareDestroyAggregateDevice(identifier)
        },
        destroyProcessTap: { identifier in
            AudioHardwareDestroyProcessTap(identifier)
        }
    )
}
