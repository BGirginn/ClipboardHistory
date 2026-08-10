import Foundation

struct DiskDeviceRate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isExternal: Bool
    let readBytesPerSecond: Double
    let writtenBytesPerSecond: Double
}
