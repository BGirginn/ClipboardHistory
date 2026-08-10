import Foundation

@MainActor
final class BrowserAudioBridge: BrowserAudioBridging {
    private struct ExtensionMessage: Decodable {
        let version: Int
        let type: String
        let source: String?
        let tabs: [BrowserAudioTab]
    }

    private struct BrowserCommand: Encodable {
        let id: String
        let volume: Double?
        let action: String?
    }

    private struct HostResponse: Encodable {
        let version = 1
        let commands: [BrowserCommand]
    }

    var tabsDidChange: (([BrowserAudioTab]) -> Void)?

    private let requestName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Request")
    private let responseName = Notification.Name("com.brgirgin.ClipboardHistory.BrowserAudio.Response")
    private var desiredVolumes: [String: Double] = [:]
    private var tabsBySource: [String: [BrowserAudioTab]] = [:]
    private var pendingActivations: Set<String> = []
    private var observer: NSObjectProtocol?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: requestName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let requestID = notification.object as? String,
                  let payload = notification.userInfo?["payload"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.handle(requestID: requestID, payload: payload)
            }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        tabsBySource.removeAll()
        desiredVolumes.removeAll()
        pendingActivations.removeAll()
        tabsDidChange?([])
    }

    func setVolume(_ volume: Double, tabID: String) {
        desiredVolumes[tabID] = min(max(volume, 0), 100)
    }

    func activate(tabID: String) {
        pendingActivations.insert(tabID)
    }

    func handle(requestID: String, payload: String) {
        guard payload.utf8.count <= 256 * 1024,
              let data = payload.data(using: .utf8),
              let message = try? decoder.decode(ExtensionMessage.self, from: data),
              message.version == 1,
              message.type == "state" else { return }
        let source = normalizedSource(message.source, tabs: message.tabs)
        let controllableTabs = message.tabs
            .filter { $0.canSetVolume && !$0.id.isEmpty && !$0.title.isEmpty }
            .prefix(128)
        tabsBySource[source] = Array(controllableTabs)
        let tabs = tabsBySource.values
            .flatMap { $0 }
            .sorted {
                if $0.browser == $1.browser { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return $0.browser.localizedStandardCompare($1.browser) == .orderedAscending
            }
        let activeIDs = Set(tabs.map(\.id))
        desiredVolumes = desiredVolumes.filter { activeIDs.contains($0.key) }
        tabsDidChange?(tabs.map { tab in
            guard let desired = desiredVolumes[tab.id] else { return tab }
            var adjusted = tab
            adjusted.volume = desired
            adjusted.isMuted = desired == 0
            return adjusted
        })
        let response = HostResponse(
            commands: desiredVolumes.map {
                BrowserCommand(id: $0.key, volume: $0.value, action: nil)
            } + pendingActivations.map {
                BrowserCommand(id: $0, volume: nil, action: "activate")
            }
        )
        pendingActivations.removeAll()
        let responsePayload = (try? encoder.encode(response)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "{\"version\":1,\"commands\":[]}"
        DistributedNotificationCenter.default().postNotificationName(
            responseName,
            object: requestID,
            userInfo: ["payload": responsePayload],
            deliverImmediately: true
        )
    }

    private func normalizedSource(_ source: String?, tabs: [BrowserAudioTab]) -> String {
        let candidate = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty { return String(candidate.prefix(64)) }
        return String((tabs.first?.browser ?? "unknown").prefix(64))
    }
}
