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

    private var desiredVolumes: [String: Double] = [:]
    private var tabsBySource: [String: [BrowserAudioTab]] = [:]
    private var pendingActivations: Set<String> = []
    private var connection: NSXPCConnection?
    private var endpoint: BrowserAudioControllerEndpoint?
    private var reconnectTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func start() {
        guard connection == nil else { return }
        connect()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        endpoint = nil
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

    func handle(requestID _: String, payload: String) {
        _ = handle(payload: Data(payload.utf8))
    }

    func handle(payload: Data) -> Data? {
        guard payload.count <= BrowserAudioBridgeXPC.maximumMessageSize,
              let message = try? decoder.decode(ExtensionMessage.self, from: payload),
              message.version == 1,
              message.type == "state" else { return nil }
        let source = normalizedSource(message.source, tabs: message.tabs)
        let controllableTabs = message.tabs
            .filter {
                $0.canSetVolume
                    && !$0.title.isEmpty
                    && isValid(tabID: $0.id, source: source)
            }
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
        return try? encoder.encode(response)
    }

    private func connect() {
        let connection = NSXPCConnection(serviceName: BrowserAudioBridgeXPC.serviceName)
        let reconnectRelay = BrowserAudioReconnectRelay { [weak self] in
            self?.scheduleReconnect()
        }
        connection.remoteObjectInterface = BrowserAudioBridgeXPC.serviceInterface()
        connection.exportedInterface = BrowserAudioBridgeXPC.controllerInterface()
        let endpoint = BrowserAudioControllerEndpoint { [weak self] payload in
            self?.handle(payload: payload)
        }
        connection.exportedObject = endpoint
        connection.interruptionHandler = Self.reconnectHandler(reconnectRelay)
        connection.invalidationHandler = Self.reconnectHandler(reconnectRelay)
        connection.resume()
        self.connection = connection
        self.endpoint = endpoint
        let proxy = connection.remoteObjectProxyWithErrorHandler(
            Self.reconnectErrorHandler(reconnectRelay)
        ) as? BrowserAudioBridgeServiceProtocol
        proxy?.registerController(withReply: Self.registrationReply(reconnectRelay))
    }

    private func scheduleReconnect() {
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        connection = nil
        endpoint = nil
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            reconnectTask = nil
            connect()
        }
    }

    private nonisolated static func reconnectHandler(
        _ relay: BrowserAudioReconnectRelay
    ) -> @Sendable () -> Void {
        { relay.requestReconnect() }
    }

    private nonisolated static func reconnectErrorHandler(
        _ relay: BrowserAudioReconnectRelay
    ) -> @Sendable (Error) -> Void {
        { _ in relay.requestReconnect() }
    }

    private nonisolated static func registrationReply(
        _ relay: BrowserAudioReconnectRelay
    ) -> @Sendable (Bool) -> Void {
        { accepted in
            guard !accepted else { return }
            relay.requestReconnect()
        }
    }

    private func normalizedSource(_ source: String?, tabs: [BrowserAudioTab]) -> String {
        let candidate = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty { return String(candidate.prefix(64)) }
        return String((tabs.first?.browser ?? "unknown").prefix(64))
    }

    private func isValid(tabID: String, source: String) -> Bool {
        guard tabID.utf8.count <= 160 else { return false }
        if source.hasPrefix("chromium:") {
            return tabID.hasPrefix("\(source):")
                && Int(tabID.dropFirst(source.count + 1)) != nil
        }
        if source.hasPrefix("safari") {
            return tabID.hasPrefix("safari:")
        }
        return false
    }
}
