import Foundation
import IOKit

final class AppleSMCTemperatureProvider: TemperatureSensorProviding, @unchecked Sendable {
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPowerLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var memory: UInt32 = 0
    }

    private struct SMCKeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var attributes: UInt8 = 0
    }

    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct SMCKeyData {
        var key: UInt32 = 0
        var version = SMCVersion()
        var powerLimit = SMCPowerLimit()
        var keyInfo = SMCKeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private struct SensorKey: Sendable {
        let code: String
        let dataType: UInt32
        let dataSize: UInt32
    }

    private let readBytesCommand: UInt8 = 5
    private let readIndexCommand: UInt8 = 8
    private let readKeyInfoCommand: UInt8 = 9
    private let callSelector: UInt32 = 2
    private var cachedKeys: [SensorKey]?

    func readings() -> [TemperatureReading] {
        guard let connection = openConnection() else { return [] }
        defer { IOServiceClose(connection) }
        let keys: [SensorKey]
        if let cachedKeys {
            keys = cachedKeys
        } else {
            keys = discoverCPUKeys(connection: connection)
            cachedKeys = keys
        }
        return keys.compactMap { sensor in
            guard let celsius = readTemperature(sensor, connection: connection),
                  (10...130).contains(celsius) else { return nil }
            return TemperatureReading(
                id: sensor.code,
                name: sensorName(for: sensor.code),
                celsius: celsius
            )
        }
    }

    private func openConnection() -> io_connect_t? {
        for serviceClass in ["AppleSMC", "AppleSMCKeysEndpoint"] {
            let service = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching(serviceClass)
            )
            guard service != 0 else { continue }
            defer { IOObjectRelease(service) }
            var connection: io_connect_t = 0
            if IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS {
                return connection
            }
        }
        return nil
    }

    private func discoverCPUKeys(connection: io_connect_t) -> [SensorKey] {
        guard let countSensor = keyInfo(for: "#KEY", connection: connection),
              let countBytes = readBytes(for: countSensor, connection: connection),
              countBytes.count >= 4 else { return fallbackKeys(connection: connection) }
        let keyCount = Int(uint32(from: countBytes))
        guard keyCount > 0, keyCount < 100_000 else { return fallbackKeys(connection: connection) }
        var sensors: [SensorKey] = []
        for index in 0..<keyCount {
            guard let code = key(at: UInt32(index), connection: connection),
                  isCPUKey(code),
                  let sensor = keyInfo(for: code, connection: connection),
                  isTemperatureType(sensor.dataType) else { continue }
            sensors.append(sensor)
        }
        return sensors.isEmpty ? fallbackKeys(connection: connection) : sensors
    }

    private func fallbackKeys(connection: io_connect_t) -> [SensorKey] {
        let known = [
            "TC0P", "TC0D", "TC0E", "TC0F",
            "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T",
            "Tp1h", "Tp1t", "Tp1p", "Tp1E", "Te05", "Te0L", "Te0P"
        ]
        return known.compactMap { code in
            guard let info = keyInfo(for: code, connection: connection),
                  isTemperatureType(info.dataType) else { return nil }
            return info
        }
    }

    private func key(at index: UInt32, connection: io_connect_t) -> String? {
        var input = SMCKeyData()
        input.data8 = readIndexCommand
        input.data32 = index
        guard let output = call(input, connection: connection), output.result == 0 else { return nil }
        return fourCharacterString(output.key)
    }

    private func keyInfo(for code: String, connection: io_connect_t) -> SensorKey? {
        guard let key = fourCharacterCode(code) else { return nil }
        var input = SMCKeyData()
        input.key = key
        input.data8 = readKeyInfoCommand
        guard let output = call(input, connection: connection),
              output.result == 0,
              output.keyInfo.dataSize > 0,
              output.keyInfo.dataSize <= 32 else { return nil }
        return SensorKey(code: code, dataType: output.keyInfo.dataType, dataSize: output.keyInfo.dataSize)
    }

    private func readTemperature(_ sensor: SensorKey, connection: io_connect_t) -> Double? {
        guard let bytes = readBytes(for: sensor, connection: connection) else { return nil }
        return decodeTemperature(dataType: sensor.dataType, bytes: bytes)
    }

    func decodeTemperature(dataType: UInt32, bytes: [UInt8]) -> Double? {
        let type = fourCharacterString(dataType)
        switch type {
        case "sp78" where bytes.count >= 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "flt " where bytes.count >= 4:
            return Double(Float(bitPattern: uint32(from: bytes)))
        default:
            return nil
        }
    }

    private func readBytes(for sensor: SensorKey, connection: io_connect_t) -> [UInt8]? {
        guard let key = fourCharacterCode(sensor.code) else { return nil }
        var input = SMCKeyData()
        input.key = key
        input.keyInfo.dataSize = sensor.dataSize
        input.data8 = readBytesCommand
        guard let output = call(input, connection: connection), output.result == 0 else { return nil }
        let count = min(Int(sensor.dataSize), 32)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(count)) }
    }

    private func call(_ input: SMCKeyData, connection: io_connect_t) -> SMCKeyData? {
        var input = input
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    callSelector,
                    inputPointer,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPointer,
                    &outputSize
                )
            }
        }
        guard result == KERN_SUCCESS, outputSize == MemoryLayout<SMCKeyData>.stride else { return nil }
        return output
    }

    func fourCharacterCode(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func fourCharacterString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    func uint32(from bytes: [UInt8]) -> UInt32 {
        guard bytes.count >= 4 else { return 0 }
        return UInt32(bytes[0]) << 24
            | UInt32(bytes[1]) << 16
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3])
    }

    func isCPUKey(_ code: String) -> Bool {
        code.hasPrefix("Tp") || code.hasPrefix("Te") || code.hasPrefix("TC")
    }

    func isTemperatureType(_ value: UInt32) -> Bool {
        ["sp78", "fpe2", "flt "].contains(fourCharacterString(value))
    }

    func sensorName(for code: String) -> String {
        if code.hasPrefix("Te") { return String(localized: "Efficiency CPU") + " · " + code }
        if code.hasPrefix("Tp") { return String(localized: "Performance CPU") + " · " + code }
        return String(localized: "CPU Sensor") + " · " + code
    }
}
