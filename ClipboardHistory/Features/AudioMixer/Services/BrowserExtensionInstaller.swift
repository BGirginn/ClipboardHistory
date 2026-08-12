import AppKit
import Foundation

@MainActor
struct BrowserExtensionInstaller {
    private static let nativeHostName = "com.brgirgin.clipboardhistory.audiomixer"
    private static let extensionID = "cgflaocbdgjkjlnoiolchhogcaepfmpf"
    private let supportRoot: URL
    private let resourceBundle: Bundle
    private let helperURL: URL
    private let fileManager: FileManager
    private let workspace: any WorkspaceRevealing

    init(
        supportRoot: URL = .applicationSupportDirectory,
        resourceBundle: Bundle = .main,
        helperURL: URL? = nil,
        fileManager: FileManager = .default,
        workspace: any WorkspaceRevealing = SystemWorkspaceRevealer()
    ) {
        self.supportRoot = supportRoot
        self.resourceBundle = resourceBundle
        self.helperURL = helperURL ?? resourceBundle.bundleURL.appending(
            path: "Contents/Library/LoginItems/ClipboardHistoryLoginItem.app/Contents/MacOS/ClipboardHistoryLoginItem"
        )
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func install() throws -> URL {
        let supportDirectory = supportRoot
            .appending(path: "ClipboardHistory", directoryHint: .isDirectory)
        let extensionDirectory = supportDirectory
            .appending(path: "BrowserAudioExtension", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: extensionDirectory.path) {
            try fileManager.removeItem(at: extensionDirectory)
        }
        try fileManager.createDirectory(
            at: extensionDirectory,
            withIntermediateDirectories: true
        )
        for resource in extensionResources {
            guard let source = resourceBundle.url(
                forResource: resource.name,
                withExtension: resource.extension
            ) else { throw CocoaError(.fileNoSuchFile) }
            let destination = extensionDirectory.appending(path: resource.destination)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
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
        workspace.reveal([directory])
    }

    private func installNativeHostManifests() throws {
        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
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
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: "\(Self.nativeHostName).json")
            try data.write(to: destination, options: .atomic)
        }
    }

    private func nativeMessagingDirectories() -> [URL] {
        let support = supportRoot
        return [
            support.appending(path: "Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "BraveSoftware/Brave-Browser/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "Microsoft Edge/NativeMessagingHosts", directoryHint: .isDirectory),
            support.appending(path: "Arc/User Data/NativeMessagingHosts", directoryHint: .isDirectory)
        ]
    }
}
