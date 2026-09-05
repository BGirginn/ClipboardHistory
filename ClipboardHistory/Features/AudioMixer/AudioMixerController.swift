import Combine
import CoreAudio
import Foundation
import SafariServices

@MainActor
final class AudioMixerController: ObservableObject {
    typealias SafariPreferencesOpener = (String, @escaping @Sendable (Error?) -> Void) -> Void
    @Published private(set) var applications: [AudioApplication] = []
    @Published var browserTabs: [BrowserAudioTab] = []
    @Published private(set) var permissionState: AudioMixerPermissionState = .notRequested
    @Published var extensionMessage: String?

    private let discovery: any AudioProcessDiscovering
    private let engine: any ProcessAudioControlling
    let browserBridge: any BrowserAudioBridging
    private let extensionInstaller: BrowserExtensionInstaller
    private let safariPreferencesOpener: SafariPreferencesOpener
    private let defaults: UserDefaults
    private let gainsKey = "audioMixer.applicationGains.v1"
    private var gains: [String: Double]
    private var preMuteGains: [String: Double] = [:]
    var browserPreMuteGains: [String: Double] = [:]
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshInterval: Duration?
    private var inFlightDiscoveryTask: Task<[AudioApplication], Never>?
    private var inFlightDiscoveryID = 0
    private var pendingVolumePreviews: [String: (volume: Double, application: AudioApplication)] = [:]
    private var volumePreviewTasks: [String: Task<Void, Never>] = [:]
    var pendingBrowserVolumePreviews: [String: Double] = [:]
    var browserVolumePreviewTasks: [String: Task<Void, Never>] = [:]
    private var demands: [SamplingDemandSource: AudioMixerDemand] = [:]
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
            guard let self else { return }
            let activeTabIDs = Set(tabs.map(\.id))
            browserPreMuteGains = browserPreMuteGains.filter { activeTabIDs.contains($0.key) }
            guard browserTabs != tabs else { return }
            browserTabs = tabs
        }
        self.browserBridge.connectionMessageDidChange = { [weak self] message in
            self?.extensionMessage = message
        }
        self.engine.setFailureHandler { [weak self] bundleID, error in
            guard let self else { return }
            permissionState = permissionState(for: error)
            appliedProcessIDsByBundle.removeValue(forKey: bundleID)
            updateActivePipelineDemand()
            updateApplication(bundleID) {
                $0.controlState = .failed(error.localizedDescription)
            }
        }
        self.browserBridge.start()
        let discoveryRelay = MainActorSignalRelay { [weak self] in
            guard let self,
                  !demands.isEmpty || gains.values.contains(where: { $0 < 100 }) else { return }
            Task {
                await refreshApplications()
            }
        }
        self.discovery.startObservingChanges(discoveryRelay.callback())
        if gains.values.contains(where: { $0 < 100 }) {
            Task { [weak self] in
                await self?.refreshApplications()
            }
        }
    }

    var demandCount: Int { demands.count }
    var isRefreshing: Bool { refreshTask != nil }
    var outputApplications: [AudioApplication] {
        applications.filter(\.isProducingOutput)
    }

    var isEverythingMuted: Bool {
        let outputApplications = outputApplications
        return (!outputApplications.isEmpty || !browserTabs.isEmpty)
            && outputApplications.allSatisfy(\.isMuted)
            && browserTabs.allSatisfy(\.isMuted)
    }

    var hasActiveUserIntervention: Bool {
        gains.values.contains { $0 < 100 }
            || applications.contains { $0.isMuted || $0.volume < 100 }
            || browserTabs.contains { $0.isMuted || $0.volume < 100 }
    }

    func startRefreshing() {
        setDemand(.detail, for: SamplingDemandSource(id: "legacy-detail"))
    }

    func stopRefreshing() {
        setDemand(nil, for: SamplingDemandSource(id: "legacy-detail"))
    }

    func setDemand(_ demand: AudioMixerDemand?, for source: SamplingDemandSource) {
        let previousDemand = demands[source]
        if let demand {
            demands[source] = demand
        } else {
            demands.removeValue(forKey: source)
        }
        guard previousDemand != demand else { return }
        updateRefreshTask()
    }

    func setDemand(_ demand: AudioMixerDemand, active: Bool) {
        setDemand(active ? demand : nil, for: SamplingDemandSource(id: "legacy-\(demand)"))
    }

    private func updateRefreshTask() {
        let desiredInterval = demands.isEmpty ? nil : refreshInterval
        guard desiredInterval != activeRefreshInterval else { return }
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshInterval = desiredInterval
        guard let desiredInterval else {
            cancelInFlightDiscovery()
            return
        }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshApplications()
                do {
                    try await Task.sleep(for: desiredInterval)
                } catch {
                    return
                }
            }
        }
    }

    private var refreshInterval: Duration {
        if demands.values.contains(.detail) { return .seconds(2) }
        if demands.values.contains(.controlCenter) { return .seconds(5) }
        return .seconds(10)
    }

    @discardableResult
    func refreshApplications() async -> Bool {
        let discoveryTask: Task<[AudioApplication], Never>
        let discoveryID: Int
        if let inFlightDiscoveryTask {
            discoveryTask = inFlightDiscoveryTask
            discoveryID = inFlightDiscoveryID
        } else {
            inFlightDiscoveryID += 1
            discoveryID = inFlightDiscoveryID
            discoveryTask = Task { [discovery] in
                await discovery.applications()
            }
            inFlightDiscoveryTask = discoveryTask
        }
        let discovered = await discoveryTask.value
        guard discoveryID == inFlightDiscoveryID,
              inFlightDiscoveryTask != nil else { return false }
        inFlightDiscoveryTask = nil
        let existingByBundleID = Dictionary(
            applications.map { ($0.bundleID, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let updatedApplications = discovered.map { application in
            var application = application
            let storedGain = gains[application.bundleID] ?? 100
            application.volume = storedGain
            application.isMuted = storedGain == 0
            if let existing = existingByBundleID[application.bundleID] {
                application.controlState = existing.controlState
            }
            return application
        }
        if applications != updatedApplications {
            applications = updatedApplications
        }
        let activeBundles = Set(updatedApplications.map(\.bundleID))
        let producingBundles = Set(
            updatedApplications.lazy.filter(\.isProducingOutput).map(\.bundleID)
        )
        let stoppedBundles = Set(appliedProcessIDsByBundle.keys).subtracting(producingBundles)
        for bundleID in stoppedBundles {
            engine.stopControlling(bundleID: bundleID)
        }
        appliedProcessIDsByBundle = appliedProcessIDsByBundle.filter {
            producingBundles.contains($0.key)
        }
        preMuteGains = preMuteGains.filter { activeBundles.contains($0.key) }
        restoreStoredGainsIfNeeded()
        return true
    }

    func setVolume(_ volume: Double, for application: AudioApplication) {
        volumePreviewTasks.removeValue(forKey: application.bundleID)?.cancel()
        pendingVolumePreviews.removeValue(forKey: application.bundleID)
        applyVolume(volume, for: application, persists: true)
    }

    func previewVolume(_ volume: Double, for application: AudioApplication) {
        let bundleID = application.bundleID
        pendingVolumePreviews[bundleID] = (volume, application)
        guard volumePreviewTasks[bundleID] == nil else { return }
        volumePreviewTasks[bundleID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(33))
            } catch {
                return
            }
            guard let self,
                  let pending = pendingVolumePreviews.removeValue(forKey: bundleID) else { return }
            volumePreviewTasks.removeValue(forKey: bundleID)
            applyVolume(pending.volume, for: pending.application, persists: false)
        }
    }

    private func applyVolume(
        _ volume: Double,
        for application: AudioApplication,
        persists: Bool
    ) {
        let normalized = min(max(volume, 0), 100)
        let previousVolume = applications.first(where: { $0.bundleID == application.bundleID })?.volume
            ?? application.volume
        if persists {
            updateApplication(application.bundleID) {
                $0.volume = normalized
                $0.isMuted = normalized == 0
                $0.controlState = normalized == 100 ? .native : .starting
            }
        }
        do {
            try engine.setGain(
                normalized / 100,
                for: application.processObjectIDs,
                bundleID: application.bundleID
            )
            guard persists else { return }
            permissionState = .requesting
            if gains[application.bundleID] != normalized {
                gains[application.bundleID] = normalized
                defaults.set(gains, forKey: gainsKey)
            }
            if normalized == 100 {
                appliedProcessIDsByBundle.removeValue(forKey: application.bundleID)
            } else {
                appliedProcessIDsByBundle[application.bundleID] = application.processObjectIDs
            }
            updateActivePipelineDemand()
            permissionState = .ready
            updateApplication(application.bundleID) {
                $0.controlState = normalized == 100 ? .native : .controlled
            }
        } catch {
            guard persists else {
                permissionState = permissionState(for: error)
                updateApplication(application.bundleID) {
                    $0.controlState = .failed(error.localizedDescription)
                }
                return
            }
            appliedProcessIDsByBundle.removeValue(forKey: application.bundleID)
            updateActivePipelineDemand()
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

    func toggleMuteAll() {
        guard !outputApplications.isEmpty || !browserTabs.isEmpty else {
            Task { [weak self] in
                guard let self else { return }
                await refreshApplications()
                guard !outputApplications.isEmpty || !browserTabs.isEmpty else { return }
                toggleMuteAllLoadedOutputs()
            }
            return
        }
        toggleMuteAllLoadedOutputs()
    }

    private func toggleMuteAllLoadedOutputs() {
        if isEverythingMuted {
            for application in outputApplications {
                setVolume(preMuteGains[application.bundleID] ?? 100, for: application)
            }
            for tab in browserTabs {
                setBrowserVolume(browserPreMuteGains[tab.id] ?? 100, tab: tab)
            }
            preMuteGains.removeAll()
            browserPreMuteGains.removeAll()
        } else {
            preMuteGains = Dictionary(
                outputApplications.map { ($0.bundleID, $0.volume) },
                uniquingKeysWith: { _, latest in latest }
            )
            browserPreMuteGains = Dictionary(
                browserTabs.map { ($0.id, $0.volume) },
                uniquingKeysWith: { _, latest in latest }
            )
            for application in outputApplications {
                setVolume(0, for: application)
            }
            for tab in browserTabs {
                setBrowserVolume(0, tab: tab)
            }
        }
    }

    func resetAll() {
        guard !applications.isEmpty else {
            Task { [weak self] in
                guard let self else { return }
                await refreshApplications()
                resetLoadedApplications()
            }
            return
        }
        resetLoadedApplications()
    }

    private func resetLoadedApplications() {
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
            browserBridge.start()
            extensionMessage = String(
                localized: "Extension files are ready. Open your browser's Extensions page, enable Developer Mode, then choose Load unpacked and select the revealed folder."
            )
        } catch {
            extensionMessage = error.localizedDescription
        }
    }

    func openSafariExtensionSettings() {
        browserBridge.start()
        safariPreferencesOpener("com.brgirgin.ClipboardHistory.SafariExtension") { [weak self] error in
            Task { @MainActor in
                self?.extensionMessage = error?.localizedDescription
                    ?? String(
                        localized: "Enable ClipboardHistory Safari Audio, then allow access only on sites you want to control."
                    )
            }
        }
    }

    func stop() {
        demands.removeAll()
        updateRefreshTask()
        cancelInFlightDiscovery()
        volumePreviewTasks.values.forEach { $0.cancel() }
        volumePreviewTasks.removeAll()
        pendingVolumePreviews.removeAll()
        browserVolumePreviewTasks.values.forEach { $0.cancel() }
        browserVolumePreviewTasks.removeAll()
        pendingBrowserVolumePreviews.removeAll()
        browserBridge.stop()
        discovery.stopObservingChanges()
        engine.stopAll()
    }

    private func updateApplication(_ bundleID: String, mutation: (inout AudioApplication) -> Void) {
        guard let index = applications.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        var updated = applications[index]
        mutation(&updated)
        guard updated != applications[index] else { return }
        applications[index] = updated
    }

    private func cancelInFlightDiscovery() {
        inFlightDiscoveryID += 1
        inFlightDiscoveryTask?.cancel()
        inFlightDiscoveryTask = nil
    }

    private func restoreStoredGainsIfNeeded() {
        for application in applications where application.isProducingOutput && application.volume < 100 {
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
        updateActivePipelineDemand()
    }

    private func updateActivePipelineDemand() {
        setDemand(
            appliedProcessIDsByBundle.isEmpty ? nil : .activePipeline,
            for: .activeAudioPipeline
        )
    }

    private func permissionState(for error: Error) -> AudioMixerPermissionState {
        if case let ProcessAudioEngineError.tapCreationFailed(status) = error,
           status == kAudioDevicePermissionsError {
            return .denied
        }
        return .failed(error.localizedDescription)
    }
}
