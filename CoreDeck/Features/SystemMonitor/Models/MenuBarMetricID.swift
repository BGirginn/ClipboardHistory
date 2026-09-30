import Foundation

enum MenuBarMetricID: String, CaseIterable, Codable, Identifiable {
    case cpu
    case memory
    case temperature
    case networkDownload
    case networkUpload
    case diskRead
    case diskWrite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .temperature: String(localized: "Temperature")
        case .networkDownload: String(localized: "Download")
        case .networkUpload: String(localized: "Upload")
        case .diskRead: String(localized: "Disk Read")
        case .diskWrite: String(localized: "Disk Write")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .temperature: "thermometer.medium"
        case .networkDownload: "arrow.down"
        case .networkUpload: "arrow.up"
        case .diskRead: "arrow.down.to.line.compact"
        case .diskWrite: "arrow.up.to.line.compact"
        }
    }

    var menuBarTextLabel: String? {
        switch self {
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "RAM")
        default: nil
        }
    }

    var menuBarSymbol: String? {
        switch self {
        case .cpu, .memory, .temperature: nil
        default: systemImage
        }
    }

    func menuBarSegmentWidth(formats: MetricFormatPreferences) -> CGFloat {
        switch self {
        case .cpu: 28
        case .memory: formats.memory == .usedAndTotal ? 68 : 28
        case .temperature: 40
        case .networkDownload, .networkUpload, .diskRead, .diskWrite: 68
        }
    }

    func menuBarStandaloneWidth(formats: MetricFormatPreferences) -> CGFloat {
        menuBarSegmentWidth(formats: formats) + 4
    }
}
