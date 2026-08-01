import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardMonitor(
        _ monitor: ClipboardMonitor,
        didReceive content: ClipboardContent,
        identity: ClipboardPasteboardIdentity
    )
}

@MainActor
final class ClipboardMonitor {
    static let pollingInterval: TimeInterval = 0.5

    weak var delegate: ClipboardMonitorDelegate?
    var shouldCaptureFromApplication: ((String?) -> Bool)?
    var didIgnoreNextChange: (() -> Void)?

    private let pasteboard: any ClipboardPasteboard
    private let processingService: any ClipboardContentProcessing
    private let timerScheduler: any RepeatingTimerScheduling
    private var previousChangeCount: Int
    private var lastDeliveredChangeCount = 0
    private var ignoresNextChange = false
    private var timer: (any RepeatingTimerToken)?
    var ignoredPasteboardTypes: Set<String> = ClipboardMonitor.alwaysIgnoredPasteboardTypes

    init(
        pasteboard: any ClipboardPasteboard = NSPasteboard.general,
        processingService: any ClipboardContentProcessing = ClipboardProcessingService(),
        timerScheduler: any RepeatingTimerScheduling = SystemRepeatingTimerScheduler()
    ) {
        self.pasteboard = pasteboard
        self.processingService = processingService
        self.timerScheduler = timerScheduler
        previousChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        previousChangeCount = pasteboard.changeCount
        timer = timerScheduler.schedule(
            interval: Self.pollingInterval,
            tolerance: 0.1
        ) { [weak self] in self?.pollNow() }
        AppLog.clipboard.debug("Clipboard monitoring started")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        AppLog.clipboard.debug("Clipboard monitoring stopped")
    }

    func pollNow() {
        Task { [weak self] in
            await self?.pollNowAndWait()
        }
    }

    func pollNowAndWait() async {
        let changeCount = pasteboard.changeCount
        guard changeCount != previousChangeCount else { return }
        previousChangeCount = changeCount

        if ignoresNextChange {
            ignoresNextChange = false
            didIgnoreNextChange?()
            AppLog.clipboard.notice("Clipboard change ignored once by user request")
            return
        }
        let presentTypes = Set(pasteboard.types?.map { $0.rawValue.lowercased() } ?? [])
        guard presentTypes.isDisjoint(with: ignoredPasteboardTypes) else {
            AppLog.clipboard.notice("Clipboard change ignored by pasteboard type policy")
            return
        }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard shouldCaptureFromApplication?(source) ?? true else {
            AppLog.clipboard.notice("Clipboard change excluded by privacy policy")
            return
        }
        guard let rawContent = readSupportedContent() else {
            AppLog.clipboard.debug("Unsupported clipboard format ignored")
            return
        }

        guard let content = await processingService.process(
            rawContent,
            sourceBundleIdentifier: source
        ) else { return }
        guard pasteboard.changeCount == changeCount else {
            AppLog.clipboard.debug("Stale clipboard processing result ignored")
            return
        }
        guard changeCount >= lastDeliveredChangeCount else { return }
        lastDeliveredChangeCount = changeCount
        delegate?.clipboardMonitor(
            self,
            didReceive: content,
            identity: ClipboardPasteboardIdentity(changeCount: changeCount)
        )
    }

    var currentIdentity: ClipboardPasteboardIdentity {
        ClipboardPasteboardIdentity(changeCount: pasteboard.changeCount)
    }

    func ignoreNextCopy() {
        ignoresNextChange = true
    }

    func clearCurrentContent(if identity: ClipboardPasteboardIdentity) -> Bool {
        guard currentIdentity == identity else { return false }
        _ = pasteboard.clearContents()
        previousChangeCount = pasteboard.changeCount
        return true
    }

    private func readSupportedContent() -> ClipboardRawContent? {
        if let fileContent = readFiles() {
            return fileContent
        }
        if let pdfData = pasteboard.data(forType: .pdf), !pdfData.isEmpty {
            return .pdf(data: pdfData)
        }
        let images = readImages()
        if !images.isEmpty {
            return .images(data: images)
        }
        let rtfData = pasteboard.data(forType: .rtf)
        let htmlData = pasteboard.data(forType: .html)
        if let text = pasteboard.string(forType: .string)
            ?? plainTextFallback(rtfData: rtfData, htmlData: htmlData) {
            return .text(
                value: text,
                rtfData: rtfData,
                htmlData: htmlData
            )
        }
        return nil
    }

    private func readFiles() -> ClipboardRawContent? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options),
              !objects.isEmpty else { return nil }
        let urls = objects.compactMap { ($0 as? NSURL) as URL? }
        guard !urls.isEmpty else { return nil }
        let bookmarks = urls.compactMap { url in
            try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        return .files(urls: urls, bookmarks: bookmarks)
    }

    private func readImages() -> [Data] {
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            .init(UTType.jpeg.identifier),
            .init(UTType.heic.identifier),
            .init(UTType.gif.identifier),
            .init(UTType.bmp.identifier)
        ]
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            imageTypes.lazy.compactMap { item.data(forType: $0) }.first
        }
    }

    func plainTextFallback(rtfData: Data?, htmlData: Data?) -> String? {
        if let rtfData,
           let attributed = try? NSAttributedString(
               data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attributed.string
        }
        guard let htmlData,
              let sanitized = HTMLSanitizer.sanitize(htmlData),
              let html = String(data: sanitized, encoding: .utf8) else { return nil }
        return HTMLSanitizer.plainText(fromSanitizedHTML: html)
    }

    deinit {
        timer?.cancel()
    }

    private static let alwaysIgnoredPasteboardTypes: Set<String> = [
        "org.nspasteboard.transienttype",
        "org.nspasteboard.concealedtype",
        "org.nspasteboard.autogeneratedtype"
    ]
}
