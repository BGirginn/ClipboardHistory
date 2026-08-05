@MainActor
protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardMonitor(
        _ monitor: ClipboardMonitor,
        didReceive content: ClipboardContent,
        identity: ClipboardPasteboardIdentity
    )
}
