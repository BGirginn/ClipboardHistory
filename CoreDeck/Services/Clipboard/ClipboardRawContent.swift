import Foundation

enum ClipboardRawContent: Sendable {
    case text(value: String, rtfData: Data?, htmlData: Data?)
    case images(data: [Data])
    case pdf(data: Data)
    case files(urls: [URL], bookmarks: [Data])
}
