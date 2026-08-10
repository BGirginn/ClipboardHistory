import AppKit
import CoreAudio
import Foundation

struct CoreAudioProcessDiscovery: AudioProcessDiscovering {
    func applications() -> [AudioApplication] {
        audioProcessObjectIDs().compactMap(application(for:)).sorted {
            if $0.isProducingOutput != $1.isProducingOutput {
                return $0.isProducingOutput && !$1.isProducingOutput
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func audioProcessObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr, size > 0 else { return [] }
        var values = Array(repeating: AudioObjectID(0), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &values
        ) == noErr else { return [] }
        return values
    }

    private func application(for objectID: AudioObjectID) -> AudioApplication? {
        guard let pid: pid_t = scalarProperty(
            objectID,
            selector: kAudioProcessPropertyPID,
            scope: kAudioObjectPropertyScopeGlobal
        ), pid != getpid() else { return nil }
        let running: UInt32 = scalarProperty(
            objectID,
            selector: kAudioProcessPropertyIsRunningOutput,
            scope: kAudioObjectPropertyScopeGlobal
        ) ?? 0
        let reportedBundleID = stringProperty(objectID, selector: kAudioProcessPropertyBundleID)
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let bundleID = reportedBundleID ?? runningApplication?.bundleIdentifier ?? "pid.\(pid)"
        let name = runningApplication?.localizedName
            ?? bundleID.split(separator: ".").last.map(String.init)
            ?? String(localized: "Unknown Application")
        return AudioApplication(
            id: objectID,
            processID: pid,
            bundleID: bundleID,
            name: name,
            isProducingOutput: running != 0,
            volume: 100,
            isMuted: false,
            controlState: .native
        )
    }

    private func scalarProperty<Value>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Value?
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : nil
    }

    private func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String : nil
    }
}
