import XCTest

@testable import ClipboardHistory

@MainActor
final class BrowserExtensionInstallerTests: XCTestCase {
    func testInstallIsReplaceableAndWritesScopedNativeHostManifests() throws {
        let root = temporaryRoot()
        let workspace = BrowserInstallerWorkspaceSpy()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = BrowserExtensionInstaller(
            supportRoot: root,
            resourceBundle: .main,
            workspace: workspace
        )

        let extensionDirectory = try installer.install()
        XCTAssertEqual(extensionDirectory.deletingLastPathComponent().lastPathComponent, "ClipboardHistory")
        let expectedResources = [
            "manifest.json", "service-worker.js", "offscreen.html", "offscreen.js",
            "popup.html", "popup.js", "_locales/en/messages.json", "_locales/tr/messages.json"
        ]
        for relativePath in expectedResources {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: extensionDirectory.appending(path: relativePath).path
                )
            )
        }
        try Data("stale".utf8).write(to: extensionDirectory.appending(path: "stale.txt"))
        try installer.revealExtensionDirectory()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: extensionDirectory.appending(path: "stale.txt").path)
        )
        XCTAssertEqual(workspace.revealed, [[extensionDirectory]])

        let browserDirectories = [
            "Google/Chrome/NativeMessagingHosts",
            "BraveSoftware/Brave-Browser/NativeMessagingHosts",
            "Microsoft Edge/NativeMessagingHosts",
            "Arc/User Data/NativeMessagingHosts"
        ]
        for relativePath in browserDirectories {
            let manifestURL = root
                .appending(path: relativePath, directoryHint: .isDirectory)
                .appending(path: "com.brgirgin.clipboardhistory.audiomixer.json")
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
            )
            XCTAssertEqual(object["name"] as? String, "com.brgirgin.clipboardhistory.audiomixer")
            XCTAssertEqual(object["type"] as? String, "stdio")
            XCTAssertEqual(
                object["allowed_origins"] as? [String],
                ["chrome-extension://cgflaocbdgjkjlnoiolchhogcaepfmpf/"]
            )
        }
    }

    func testMissingResourceAndHelperFailWithoutWritingOutsideInjectedRoot() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let unrelatedBundle = try XCTUnwrap(
            Bundle(path: "/System/Library/Frameworks/Foundation.framework")
        )
        let missingResource = BrowserExtensionInstaller(
            supportRoot: root,
            resourceBundle: unrelatedBundle,
            helperURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        XCTAssertThrowsError(try missingResource.install())

        let missingHelper = BrowserExtensionInstaller(
            supportRoot: root,
            resourceBundle: .main,
            helperURL: root.appending(path: "missing-helper")
        )
        XCTAssertThrowsError(try missingHelper.install())
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "BrowserExtensionInstallerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

@MainActor
private final class BrowserInstallerWorkspaceSpy: WorkspaceRevealing {
    private(set) var revealed: [[URL]] = []

    func reveal(_ urls: [URL]) {
        revealed.append(urls)
    }
}
