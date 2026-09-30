import AppKit
import Foundation

@MainActor
protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    var types: [NSPasteboard.PasteboardType]? { get }

    func clearContents() -> Int
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func readObjects(
        forClasses classArray: [AnyClass],
        options: [NSPasteboard.ReadingOptionKey: Any]?
    ) -> [Any]?
}

extension NSPasteboard: ClipboardPasteboard {}
