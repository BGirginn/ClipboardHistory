import AppKit
import CoreAudio
import Foundation

final class CoreAudioProcessDiscovery: AudioProcessDiscovering, @unchecked Sendable {
    private struct ProcessRecord {
        let objectID: AudioObjectID
        let processID: pid_t
        let bundleID: String
        let name: String
        let isProducingOutput: Bool
    }

    private let listenerQueue = DispatchQueue(label: "com.brgirgin.ClipboardHistory.audio-discovery")
    private var processListListener: AudioObjectPropertyListenerBlock?

    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) {
        stopObservingChanges()
        var address = Self.processListAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            listener
        ) == noErr else { return }
        processListListener = listener
    }

    func stopObservingChanges() {
        guard let processListListener else { return }
        var address = Self.processListAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            processListListener
        )
        self.processListListener = nil
    }

    private static var processListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func applications() -> [AudioApplication] {
        let records = audioProcessObjectIDs().compactMap(processRecord(for:))
        return Dictionary(grouping: records, by: \.bundleID).compactMap { bundleID, group in
            guard let representative = group.first else { return nil }
            let objectIDs = Set(group.map(\.objectID))
            guard let stableID = objectIDs.min() else { return nil }
            return AudioApplication(
                id: stableID,
                processObjectIDs: objectIDs,
                processID: representative.processID,
                bundleID: bundleID,
                name: representative.name,
                isProducingOutput: group.contains(where: \.isProducingOutput),
                volume: 100,
                isMuted: false,
                controlState: .native
            )
        }.sorted {
            if $0.isProducingOutput != $1.isProducingOutput {
                return $0.isProducingOutput && !$1.isProducingOutput
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func audioProcessObjectIDs() -> [AudioObjectID] {
        var address = Self.processListAddress
        var requestedSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &requestedSize
        ) == noErr,
        requestedSize > 0,
        requestedSize.isMultiple(of: UInt32(MemoryLayout<AudioObjectID>.size)) else { return [] }

        var values = Array(
            repeating: AudioObjectID(0),
            count: Int(requestedSize) / MemoryLayout<AudioObjectID>.size
        )
        var returnedSize = requestedSize
        let status = values.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudio_ParamError }
            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &returnedSize,
                baseAddress
            )
        }
        guard status == noErr,
              returnedSize <= requestedSize,
              returnedSize.isMultiple(of: UInt32(MemoryLayout<AudioObjectID>.size)) else { return [] }
        return Array(values.prefix(Int(returnedSize) / MemoryLayout<AudioObjectID>.size))
            .filter { $0 != 0 }
    }

    private func processRecord(for objectID: AudioObjectID) -> ProcessRecord? {
        guard let pid = processIDProperty(objectID), pid != getpid() else { return nil }
        let running = uint32Property(
            objectID,
            selector: kAudioProcessPropertyIsRunningOutput
        ) ?? 0
        let reportedBundleID = stringProperty(objectID, selector: kAudioProcessPropertyBundleID)
            .flatMap { $0.isEmpty ? nil : $0 }
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let identity = AudioApplicationIdentityResolver.resolve(
            reportedBundleID: reportedBundleID ?? runningApplication?.bundleIdentifier ?? "pid.\(pid)",
            runningName: runningApplication?.localizedName,
            bundleURL: runningApplication?.bundleURL,
            executableURL: runningApplication?.executableURL
                ?? AudioApplicationIdentityResolver.executableURL(for: pid)
        )
        return ProcessRecord(
            objectID: objectID,
            processID: pid,
            bundleID: identity.bundleID,
            name: identity.name,
            isProducingOutput: running != 0
        )
    }

    private func processIDProperty(_ objectID: AudioObjectID) -> pid_t? {
        var value = pid_t(0)
        guard readScalar(
            objectID,
            selector: kAudioProcessPropertyPID,
            into: &value
        ) else { return nil }
        return value
    }

    private func uint32Property(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var value = UInt32(0)
        guard readScalar(objectID, selector: selector, into: &value) else { return nil }
        return value
    }

    private func readScalar<Value>(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        into value: inout Value
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let expectedSize = UInt32(MemoryLayout<Value>.size)
        var returnedSize = expectedSize
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &returnedSize, pointer)
        }
        return status == noErr && returnedSize == expectedSize
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
        var value: CFString?
        let expectedSize = UInt32(MemoryLayout<CFString?>.size)
        var returnedSize = expectedSize
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &returnedSize, pointer)
        }
        guard status == noErr, returnedSize == expectedSize else { return nil }
        return value as String?
    }
}
