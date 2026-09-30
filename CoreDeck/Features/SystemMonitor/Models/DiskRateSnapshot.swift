import Foundation

struct DiskRateSnapshot: Equatable, Sendable {
    var readBytesPerSecond: Double
    var writtenBytesPerSecond: Double
    var devices: [DiskDeviceRate]

    static let empty = DiskRateSnapshot(
        readBytesPerSecond: 0,
        writtenBytesPerSecond: 0,
        devices: []
    )

    init(
        readBytesPerSecond: Double,
        writtenBytesPerSecond: Double,
        devices: [DiskDeviceRate] = []
    ) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writtenBytesPerSecond = writtenBytesPerSecond
        self.devices = devices
    }
}
