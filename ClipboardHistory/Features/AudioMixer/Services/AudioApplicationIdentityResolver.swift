import AppKit
import Darwin
import Foundation

enum AudioApplicationIdentityResolver {
    static func resolve(
        reportedBundleID: String?,
        runningName: String?,
        bundleURL: URL?,
        executableURL: URL?
    ) -> (bundleID: String, name: String) {
        let applicationURL = outermostApplicationURL(in: bundleURL)
            ?? outermostApplicationURL(in: executableURL)
        let applicationBundle = applicationURL.flatMap(Bundle.init(url:))
        let fallbackBundleID = normalizedBundleID(reportedBundleID)
        let bundleID = canonicalBundleID(
            applicationBundle?.bundleIdentifier ?? fallbackBundleID
        )
        let name = applicationURL.map(applicationName)
            ?? usableRunningName(runningName)
            ?? installedApplicationName(bundleID: bundleID)
            ?? String(localized: "Unknown Application")
        return (bundleID, name)
    }

    static func executableURL(for processID: pid_t) -> URL? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = path.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return proc_pidpath(processID, baseAddress, UInt32(buffer.count))
        }
        guard count > 0 else { return nil }
        let bytes = path.prefix(Int(count)).map(UInt8.init(bitPattern:))
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
    }

    private static func outermostApplicationURL(in url: URL?) -> URL? {
        guard var candidate = url?.standardizedFileURL else { return nil }
        var result: URL?
        while candidate.path != "/" {
            if candidate.pathExtension.lowercased() == "app" {
                result = candidate
            }
            candidate.deleteLastPathComponent()
        }
        return result
    }

    private static func applicationName(at url: URL) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
        return (displayName as NSString).deletingPathExtension
    }

    private static func normalizedBundleID(_ bundleID: String?) -> String {
        guard let bundleID, !bundleID.isEmpty else { return "unknown.application" }
        return bundleID
    }

    private static func canonicalBundleID(_ bundleID: String) -> String {
        let helperSuffixes = [
            ".helper.renderer",
            ".helper.plugin",
            ".helper.gpu",
            ".helper"
        ]
        let lowercased = bundleID.lowercased()
        guard let suffix = helperSuffixes.first(where: { lowercased.hasSuffix($0) }) else {
            return bundleID
        }
        return String(bundleID.dropLast(suffix.count))
    }

    private static func usableRunningName(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let lowercased = name.lowercased()
        guard !lowercased.contains(" helper"), !lowercased.hasPrefix("pid.") else { return nil }
        return name
    }

    private static func installedApplicationName(bundleID: String) -> String? {
        guard !bundleID.hasPrefix("pid."),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return applicationName(at: url)
    }
}
