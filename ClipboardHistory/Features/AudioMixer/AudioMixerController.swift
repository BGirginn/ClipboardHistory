import Combine
import CoreAudio
import Foundation
import SafariServices

@MainActor
final class AudioMixerController: ObservableObject {
    typealias SafariPreferencesOpener = (String, @escaping @Sendable (Error?) -> Void) -> Void
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var browserTabs: [BrowserAudioTab] = []
    @Published private(set) var permissionState: AudioMixerPermissionState = .notRequested
    @Published var extensionMessage: String?

    private let discovery: any AudioProcessDiscovering
    private let engine: any ProcessAudioControlling
    private let browserBridge: any BrowserAudioBridging
    private let extensionInstaller: BrowserExtensionInstaller
    private let safariPreferencesOpener: SafariPreferencesOpener
    private let defaults: UserDefaults
    private let gainsKey = "audioMixer.applicationGains.v1"
    private var gains: [String: Double]
    private var preMuteGains: [String: Double] = [:]
    private var browserPreMuteGains: [String: Double] = [:]
    private var refreshTask: Task<Void, Never>?
    private var demands: Set<AudioMixerDemand> = []
    private var appliedProcessIDsByBundle: [String: Set<AudioObjectID>] = [:]

    init(
        discovery: any AudioProcessDiscovering = CoreAudioProcessDiscovery(),
        engine: any ProcessAudioControlling = ProcessAudioEngine(),
        browserBridge: any BrowserAudioBridging = BrowserAudioBridge(),
        extensionInstaller: BrowserExtensionInstaller? = nil,
        safariPreferencesOpener: @escaping SafariPreferencesOpener = { identifier, completion in
            SFSafariApplication.showPreferencesForExtension(
                withIdentifier: identifier,
                completionHandler: completion
            )
        },
        defaults: UserDefaults = .standard
    ) {
        self.discovery = discovery
        self.engine = engine
        self.browserBridge = browserBridge
        self.extensionInstaller = extensionInstaller ?? BrowserExtensionInstaller()
        self.safariPreferencesOpener = safariPreferencesOpener
        self.defaults = defaults
        gains = defaults.dictionary(forKey: gainsKey) as? [String: Double] ?? [:]
        self.browserBridge.tabsDidChange = { [weak self] tabs in
            self?.browserTabs = tabs
        }
        self.engine.setFailureHandler { [weak self] bundleID, error in
            guard let self else { return }
            permissionState = permissionState(for: error)
            appliedProcessIDsByBundle.removeValue(forKey: bundleID)
            updateApplication(bundleID) {
                $0.controlState = .failed(error.localizedDescription)
            }
        }
        self.browserBridge.start()
        let discoveryRelay = MainActorSignalRelay { [weak self] in
            guard let self, !demands.isEmpty else { return }
            refreshApplications()
            restoreStoredGainsIfNeeded()
        }
        self.discovery.startObservingChanges(discoveryRelay.callback())
        if gains.values.contains(where: { $0 < 100 }) {
            demands.insert(.activePipeline)
            updateRefreshTask()
        }
    }

    var demandCount: Int { demands.count }
    var isRefreshing: Bool { refreshTask != nil }

    var isEverythingMuted: Bool {
        let applicationAudio = applications.filter(\.isProducingOutput)
        return !applicationAudio.isEmpty
            && applicationAudio.allSatisfy(\.isMuted)
            && browserTabs.allSatisfy(\.isMuted)
    }

    func startRefreshing() {
        setDemand(.detail, active: true)
    }

    func stopRefreshing() {
        setDemand(.detail, active: false)
    }

    func setDemand(_ demand: AudioMixerDemand, active: Bool) {
        let changed: Bool
        if active {
            changed = demands.insert(demand).inserted
        } else {
            changed = demands.remove(demand) != nil
        }
        guard changed else { return }
        updateRefreshTask()
    }

    private func updateRefreshTask() {
        refreshTask?.cancel()
        refreshTask = nil
        guard !demands.isEmpty else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                refreshApplications()
                restoreStoredGainsIfNeeded()
                do {
                    try await Task.sleep(for: refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private var refreshInterval: Duration {
        if demands.contains(.detail) { return .seconds(2) }
        if demands.contains(.controlCenter) { return .seconds(5) }
        return .seconds(10)
    }

    func refreshApplications() {
        let discovered = discovery.applications()
        applications = discovered.map { application in
            var application = application
            let storedGain = gains[application.bundleID] ?? 100
            application.volume = storedGain
            application.isMuted = storedGain == 0
            if let existing = applications.first(where: { $0.bundleID == application.bundleID }) {
                application.controlState = existing.controlState
            }
            return application
        }
        let activeBundles = Set(applications.map(\.bundleID))
        appliedProcessIDsByBundle = appliedProcessIDsByBundle.filter {
            activeBundles.contains($0.key)
        }
    }

    func setVolume(_ volume: Double, for application: AudioApplication) {
        let normalized = min(max(volume, 0), 100)
        let previousVolume = applications.first(where: { $0.bundleID == application.bundleID })?.volume
            ?? application.volume
        updateApplication(application.bundleID) {
            $0.volume = normalized
            $0.isMuted = normalized == 0
            $0.controlState = normalized == 100 ? .native : .starting
        }
        permissionState = .requesting
        do {
            try engine.setGain(
                normalized / 100,
                for: application.processObjectIDs,
                bundleID: application.bundleID
            )
            gains[application.bundleID] = normalized
            defaults.set(gains, forKey: gainsKey)
            if normalized == 100 {
                appliedProcessIDsByBundle.removeValue(forKey: application.bundleID)
            } else {
                appliedProcessIDsByBundle[application.bundleID] = application.processObjectIDs
            }
            setDemand(.activePipeline, active: gains.values.contains(where: { $0 < 100 }))
            permissionState = .ready
            updateApplication(application.bundleID) {
                $0.controlState = normalized == 100 ? .native : .controlled
            }
        } catch {
            appliedProcessIDsByBundle.removeValue(forKey: application.bundleID)
            permissionState = permissionState(for: error)
            updateApplication(application.bundleID) {
                $0.volume = previousVolume
                $0.isMuted = previousVolume == 0
                $0.controlState = .failed(error.localizedDescription)
            }
        }
    }

    func toggleMute(_ application: AudioApplication) {
        if application.isMuted {
            setVolume(max(preMuteGains.removeValue(forKey: application.bundleID) ?? 100, 1), for: application)
        } else {
            preMuteGains[application.bundleID] = application.volume
            setVolume(0, for: application)
        }
    }

    func setBrowserVolume(_ volume: Double, tab: BrowserAudioTab) {
        browserBridge.setVolume(volume, tabID: tab.id)
        if let index = browserTabs.firstIndex(where: { $0.id == tab.id }) {
            browserTabs[index].volume = min(max(volume, 0), 100)
            browserTabs[index].isMuted = volume == 0
        }
    }

    func toggleMute(_ tab: BrowserAudioTab) {
        if tab.isMuted {
            setBrowserVolume(max(browserPreMuteGains.removeValue(forKey: tab.id) ?? 100, 1), tab: tab)
        } else {
            browserPreMuteGains[tab.id] = tab.volume
            setBrowserVolume(0, tab: tab)
        }
    }

    func activate(_ tab: BrowserAudioTab) {
        browserBridge.activate(tabID: tab.id)
    }

    func effectiveVolume(for tab: BrowserAudioTab) -> Double {
        let matchingBundleIDs: Set<String>
        switch tab.browser.lowercased() {
        case "safari": matchingBundleIDs = ["com.apple.Safari"]
        case "brave": matchingBundleIDs = ["com.brave.Browser"]
        case "edge": matchingBundleIDs = ["com.microsoft.edgemac"]
        case "arc": matchingBundleIDs = ["company.thebrowser.Browser"]
        case "chromium": matchingBundleIDs = [
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser"
        ]
        default: matchingBundleIDs = ["com.google.Chrome"]
        }
        let matches = applications.filter { matchingBundleIDs.contains($0.bundleID) }
        let master = matches.count == 1 ? matches[0].volume : 100
        return master * tab.volume / 100
    }

    func toggleMuteAll() {
        if applications.isEmpty { refreshApplications() }
        if isEverythingMuted {
            for application in applications where application.isProducingOutput {
                setVolume(preMuteGains[application.bundleID] ?? 100, for: application)
            }
            for tab in browserTabs {
                setBrowserVolume(browserPreMuteGains[tab.id] ?? 100, tab: tab)
            }
            preMuteGains.removeAll()
            browserPreMuteGains.removeAll()
        } else {
            preMuteGains = Dictionary(uniqueKeysWithValues: applications.map { ($0.bundleID, $0.volume) })
            browserPreMuteGains = Dictionary(uniqueKeysWithValues: browserTabs.map { ($0.id, $0.volume) })
            for application in applications where application.isProducingOutput {
                setVolume(0, for: application)
            }
            for tab in browserTabs {
                setBrowserVolume(0, tab: tab)
            }
        }
    }

    func resetAll() {
        if applications.isEmpty { refreshApplications() }
        for application in applications {
            setVolume(100, for: application)
        }
        for tab in browserTabs {
            setBrowserVolume(100, tab: tab)
        }
    }

    func installChromiumExtension() {
        do {
            try extensionInstaller.revealExtensionDirectory()
            extensionMessage = String(localized: "Extension files are ready. Open your browser's Extensions page, enable Developer Mode, then choose Load unpacked and select the revealed folder.")
        } catch {
            extensionMessage = error.localizedDescription
        }
    }

    func openSafariExtensionSettings() {
        safariPreferencesOpener("com.brgirgin.ClipboardHistory.SafariExtension") { [weak self] error in
            Task { @MainActor in
                self?.extensionMessage = error?.localizedDescription
                    ?? String(localized: "Enable ClipboardHistory Safari Audio, then allow access only on sites you want to control.")
            }
        }
    }

    func stop() {
        demands.removeAll()
        updateRefreshTask()
        browserBridge.stop()
        discovery.stopObservingChanges()
        engine.stopAll()
    }

    private func updateApplication(_ bundleID: String, mutation: (inout AudioApplication) -> Void) {
        guard let index = applications.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        mutation(&applications[index])
    }

    private func restoreStoredGainsIfNeeded() {
        for application in applications where application.volume < 100 {
            guard appliedProcessIDsByBundle[application.bundleID] != application.processObjectIDs else {
                continue
            }
            do {
                try engine.setGain(
                    application.volume / 100,
                    for: application.processObjectIDs,
                    bundleID: application.bundleID
                )
                permissionState = .ready
                appliedProcessIDsByBundle[application.bundleID] = application.processObjectIDs
                updateApplication(application.bundleID) { $0.controlState = .controlled }
            } catch {
                appliedProcessIDsByBundle.removeValue(forKey: application.bundleID)
                permissionState = permissionState(for: error)
                updateApplication(application.bundleID) {
                    $0.controlState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func permissionState(for error: Error) -> AudioMixerPermissionState {
        if case let ProcessAudioEngineError.tapCreationFailed(status) = error,
           status == kAudioDevicePermissionsError {
            return .denied
        }
        return .failed(error.localizedDescription)
    }
}
