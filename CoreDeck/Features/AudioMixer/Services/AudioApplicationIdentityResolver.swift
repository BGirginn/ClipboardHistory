import Darwin
import Foundation

enum AudioApplicationIdentityResolver {
    static func resolve(
        reportedBundleID: String?,
        runningName: String?,
        bundleURL: URL?,
        executableURL: URL?
    ) -> (bundleID: String, name: String, applicationURL: URL)? {
        guard let applicationURL = outermostApplicationURL(in: bundleURL)
            ?? outermostApplicationURL(in: executableURL)
        else { return nil }
        guard isUserFacingApplicationURL(applicationURL) else { return nil }
        let applicationBundle = Bundle(url: applicationURL)
        let fallbackBundleID = normalizedBundleID(reportedBundleID)
        let bundleID = canonicalBundleID(
            applicationBundle?.bundleIdentifier ?? fallbackBundleID
        )
        guard !bundleID.hasPrefix("pid."), bundleID != "unknown.application" else { return nil }
        let name = applicationBundle.flatMap(localizedApplicationName)
            ?? usableRunningName(runningName)
            ?? applicationName(at: applicationURL)
        guard !name.isEmpty, name != String(localized: "Unknown Application") else { return nil }
        return (bundleID, name, applicationURL)
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

    private static func isUserFacingApplicationURL(_ url: URL) -> Bool {
        !url.standardizedFileURL.path
            .lowercased()
            .hasPrefix("/system/library/")
    }

    private static func localizedApplicationName(in bundle: Bundle) -> String? {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let value = bundle.localizedInfoDictionary?[key] as? String,
               !value.isEmpty {
                return value
            }
            if let value = bundle.object(forInfoDictionaryKey: key) as? String,
               !value.isEmpty {
                return value
            }
        }
        return nil
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

}
