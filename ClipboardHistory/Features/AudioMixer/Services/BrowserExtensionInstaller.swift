import AppKit
import Foundation

struct BrowserExtensionInstaller {
    private static let nativeHostName = "com.brgirgin.clipboardhistory.audiomixer"
    private static let extensionID = "cgflaocbdgjkjlnoiolchhogcaepfmpf"

    func install() throws -> URL {
        let supportDirectory = URL.applicationSupportDirectory
            .appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        let extensionDirectory = supportDirectory
            .appending(path: "BrowserAudioExtension", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: extensionDirectory.path) {
            try FileManager.default.removeItem(at: extensionDirectory)
        }
        try FileManager.default.createDirectory(
            at: extensionDirectory,
            withIntermediateDirectories: true
        )
        for resource in extensionResources {
            guard let source = Bundle.main.url(
                forResource: resource.name,
                withExtension: resource.extension
            ) else { throw CocoaError(.fileNoSuchFile) }
            let destination = extensionDirectory.appending(path: resource.destination)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try installNativeHostManifests()
        return extensionDirectory
    }

    private var extensionResources: [(name: String, extension: String?, destination: String)] {
        [
            ("manifest", "json", "manifest.json"),
            ("service-worker", "js", "service-worker.js"),
            ("offscreen", "html", "offscreen.html"),
            ("offscreen", "js", "offscreen.js"),
            ("popup", "html", "popup.html"),
            ("popup", "js", "popup.js"),
            ("en_messages", "json", "_locales/en/messages.json"),
            ("tr_messages", "json", "_locales/tr/messages.json")
        ]
    }

    func revealExtensionDirectory() throws {
        let directory = try install()
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func installNativeHostManifests() throws {
        let helperURL = Bundle.main.bundleURL
            .appending(path: "Contents/Library/LoginItems/ClipboardHistoryLoginItem.app/Contents/MacOS/ClipboardHistoryLoginItem")
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest: [String: Any] = [
            "name": Self.nativeHostName,
            "description": "ClipboardHistory browser audio bridge",
            "path": helperURL.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(Self.extensionID)/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        for directory in nativeMessagingDirectories() {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: "\(Self.nativeHostName).json")
            try data.write(to: destination, options: .atomic)
        }
    }

    private func nativeMessagingDirectories() -> [URL] {
        let support = URL.applicationSupportDirectory
        return [
            support.appending(path: "Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "BraveSoftware/Brave-Browser/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "Microsoft Edge/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "Arc/User Data/NativeMessagingHosts", directoryHint: .isDirectory)
        ]
    }
}
