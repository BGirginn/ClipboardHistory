import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

extension ClipboardHistoryViewModel: ClipboardMonitorDelegate {
    func clipboardMonitor(
        _ monitor: ClipboardMonitor,
        didReceive content: ClipboardContent,
        identity: ClipboardPasteboardIdentity
    ) {
        Task { [weak self] in
            await self?.insert(content, pasteboardIdentity: identity)
        }
    }
}
