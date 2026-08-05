import Foundation
import os

enum AppLog {
    static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "ClipboardHistory"
    }

    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let performance = Logger(subsystem: subsystem, category: "performance")
}
