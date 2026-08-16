import CoreAudio
import XCTest

@testable import ClipboardHistory

private final class AudioDiscoveryStub: AudioProcessDiscovering, @unchecked Sendable {
    var discovered: [AudioApplication]
    private var changeHandler: (@Sendable () -> Void)?

    init(discovered: [AudioApplication]) {
        self.discovered = discovered
    }

    func applications() -> [AudioApplication] { discovered }
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) {
        changeHandler = handler
    }
    func stopObservingChanges() { changeHandler = nil }
    func fireChange() { changeHandler?() }
}

@MainActor
private final class ProcessAudioControllerStub: ProcessAudioControlling {
    var gains: [(String, Double)] = []
    var error: Error?
    var failureHandler: (@MainActor @Sendable (String, Error) -> Void)?
    private(set) var stoppedBundles: [String] = []
    private(set) var stopAllCount = 0
    func setFailureHandler(_ handler: (@MainActor @Sendable (String, Error) -> Void)?) {
        failureHandler = handler
    }
    func setGain(_ gain: Double, for processObjectIDs: Set<AudioObjectID>, bundleID: String) throws {
        if let error { throw error }
        gains.append((bundleID, gain))
    }
    func stopControlling(bundleID: String) { stoppedBundles.append(bundleID) }
    func stopAll() { stopAllCount += 1 }
    func fail(bundleID: String, error: Error) { failureHandler?(bundleID, error) }
}

@MainActor
private final class BrowserAudioBridgeStub: BrowserAudioBridging {
    var tabsDidChange: (([BrowserAudioTab]) -> Void)?
    var volumes: [(String, Double)] = []
    var activatedIDs: [String] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func setVolume(_ volume: Double, tabID: String) { volumes.append((tabID, volume)) }
    func activate(tabID: String) { activatedIDs.append(tabID) }
}

private enum AudioTestError: LocalizedError {
    case failed
    var errorDescription: String? { "Audio pipeline failed" }
}

@MainActor
final class AudioMixerControllerTests: XCTestCase {
    func testAudioApplicationIdentityCollapsesHelperProcessIntoOwningApplication() {
        let helperURL = URL(
            fileURLWithPath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Helper.app"
        )

        let identity = AudioApplicationIdentityResolver.resolve(
            reportedBundleID: "com.brave.Browser.helper",
            runningName: "Brave Browser Helper",
            bundleURL: helperURL,
            executableURL: nil
        )

        XCTAssertEqual(identity.bundleID, "com.brave.Browser")
        XCTAssertEqual(identity.name, "Brave Browser")
    }

    func testAudioApplicationIdentityUsesApplicationNameInsteadOfPIDFallback() {
        let identity = AudioApplicationIdentityResolver.resolve(
            reportedBundleID: "pid.61433",
            runningName: nil,
            bundleURL: nil,
            executableURL: URL(
                fileURLWithPath: "/Applications/Spotify.app/Contents/MacOS/Spotify"
            )
        )

        XCTAssertEqual(identity.name, "Spotify")
    }

    func testLiveCoreAudioDiscoveryDoesNotExposeHelperProcessIdentity() {
        let applications = CoreAudioProcessDiscovery().applications()

        XCTAssertFalse(
            applications.contains { $0.bundleID.lowercased().hasSuffix(".helper") }
        )
        if let brave = applications.first(where: { $0.bundleID == "com.brave.Browser" }) {
            XCTAssertEqual(brave.name, "Brave Browser")
            XCTAssertGreaterThanOrEqual(brave.processObjectIDs.count, 1)
        }
    }

    func testBrowserBridgeMergesSourcesRejectsUncontrollableTabsAndNamespacesCommands() throws {
        let bridge = BrowserAudioBridge()
        var observed: [BrowserAudioTab] = []
        bridge.tabsDidChange = { observed = $0 }
        let chromium = """
        {"version":1,"type":"state","source":"chromium:chrome","tabs":[
          {"id":"chromium:chrome:4","browser":"Chrome","title":"Music","canSetVolume":true,"volume":100,"isMuted":false},
          {"id":"chromium:chrome:5","browser":"Chrome","title":"Protected","canSetVolume":false,"volume":100,"isMuted":false}
        ]}
        """
        let safari = """
        {"version":1,"type":"state","source":"safari","tabs":[
          {"id":"safari:4","browser":"Safari","title":"Video","canSetVolume":true,"volume":80,"isMuted":false}
        ]}
        """

        bridge.handle(requestID: UUID().uuidString, payload: chromium)
        bridge.handle(requestID: UUID().uuidString, payload: safari)

        XCTAssertEqual(Set(observed.map(\.id)), Set(["chromium:chrome:4", "safari:4"]))
        bridge.setVolume(25, tabID: "safari:4")
        bridge.handle(requestID: UUID().uuidString, payload: safari)
        XCTAssertEqual(observed.first { $0.id == "safari:4" }?.volume, 25)

        bridge.handle(requestID: UUID().uuidString, payload: "{\"version\":2,\"type\":\"state\",\"tabs\":[]}")
        XCTAssertEqual(Set(observed.map(\.id)), Set(["chromium:chrome:4", "safari:4"]))

        let oversized = Data(repeating: 0x41, count: BrowserAudioBridgeXPC.maximumMessageSize + 1)
        XCTAssertNil(bridge.handle(payload: oversized))
        XCTAssertEqual(Set(observed.map(\.id)), Set(["chromium:chrome:4", "safari:4"]))
    }

    func testBrowserBridgeCapsTabsClampsCommandsAndEndpointRepliesOnMainActor() async throws {
        let bridge = BrowserAudioBridge()
        var observed: [BrowserAudioTab] = []
        bridge.tabsDidChange = { observed = $0 }
        let tabs = (0..<130).map { index in
            BrowserAudioTab(
                id: "chromium:brave:\(index)",
                browser: "Brave",
                title: "Tab \(index)",
                canSetVolume: true,
                volume: 100,
                isMuted: false
            )
        } + [
            BrowserAudioTab(
                id: "chromium:brave:" + String(repeating: "9", count: 200),
                browser: "Brave",
                title: "Oversized",
                canSetVolume: true,
                volume: 100,
                isMuted: false
            )
        ]
        let payload = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "type": "state",
            "source": "  chromium:brave  ",
            "tabs": tabs.map {
                [
                    "id": $0.id,
                    "browser": $0.browser,
                    "title": $0.title,
                    "canSetVolume": $0.canSetVolume,
                    "volume": $0.volume,
                    "isMuted": $0.isMuted
                ] as [String: Any]
            }
        ])
        XCTAssertNotNil(bridge.handle(payload: payload))
        XCTAssertEqual(observed.count, 128)

        bridge.setVolume(-10, tabID: "chromium:brave:1")
        bridge.setVolume(150, tabID: "chromium:brave:2")
        bridge.activate(tabID: "chromium:brave:1")
        let responseData = try XCTUnwrap(bridge.handle(payload: payload))
        let response = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let commands = try XCTUnwrap(response["commands"] as? [[String: Any]])
        XCTAssertTrue(commands.contains {
            $0["id"] as? String == "chromium:brave:1" && $0["volume"] as? Double == 0
        })
        XCTAssertTrue(commands.contains {
            $0["id"] as? String == "chromium:brave:2" && $0["volume"] as? Double == 100
        })
        XCTAssertTrue(commands.contains {
            $0["id"] as? String == "chromium:brave:1"
                && $0["action"] as? String == "activate"
        })

        let replyExpectation = expectation(description: "browser endpoint reply")
        let endpoint = BrowserAudioControllerEndpoint { data in data }
        endpoint.handleBrowserAudioPayload(Data("reply".utf8)) { data in
            XCTAssertEqual(data, Data("reply".utf8))
            replyExpectation.fulfill()
        }
        await fulfillment(of: [replyExpectation], timeout: 1)
    }

    func testApplicationGainPersistsAndPipelineFailureRollsBackUI() throws {
        let suite = "AudioMixerControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let engine = ProcessAudioControllerStub()
        let controller = makeController(engine: engine, defaults: defaults)
        controller.refreshApplications()

        controller.setVolume(35, for: controller.applications[0])
        XCTAssertEqual(controller.applications[0].volume, 35)
        XCTAssertEqual(try XCTUnwrap(engine.gains.last).1, 0.35, accuracy: 0.0001)

        engine.error = AudioTestError.failed
        controller.setVolume(10, for: controller.applications[0])
        XCTAssertEqual(controller.applications[0].volume, 35)
        XCTAssertEqual(controller.applications[0].controlState, .failed("Audio pipeline failed"))
    }

    func testTabGainActivationAndBrowserMasterEffectiveVolume() {
        let engine = ProcessAudioControllerStub()
        let bridge = BrowserAudioBridgeStub()
        let controller = makeController(engine: engine, bridge: bridge)
        controller.refreshApplications()
        controller.setVolume(50, for: controller.applications[0])
        let tab = BrowserAudioTab(
            id: "safari:4",
            browser: "Safari",
            title: "Video",
            canSetVolume: true,
            volume: 40,
            isMuted: false
        )

        controller.setBrowserVolume(25, tab: tab)
        controller.activate(tab)

        XCTAssertEqual(bridge.volumes.last?.0, "safari:4")
        XCTAssertEqual(bridge.volumes.last?.1, 25)
        XCTAssertEqual(bridge.activatedIDs, ["safari:4"])
        XCTAssertEqual(controller.effectiveVolume(for: tab), 20)
    }

    func testFloatGainProcessorClampsGainAndSamples() {
        let input: [Float] = [-2, -1, -0.5, 0.5, 1, 2]
        var output = Array(repeating: Float.zero, count: input.count)
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioGainProcessor.apply(
                    input: inputBuffer.baseAddress!,
                    output: outputBuffer.baseAddress!,
                    sampleCount: input.count,
                    gain: 0.75
                )
            }
        }
        XCTAssertEqual(output, [-1, -0.75, -0.375, 0.375, 0.75, 1])
    }

    func testDemandLifecycleAndQuickMuteDiscoverApplicationsBeforeActing() {
        let engine = ProcessAudioControllerStub()
        let controller = makeController(engine: engine)
        XCTAssertFalse(controller.isRefreshing)

        controller.setDemand(.controlCenter, active: true)
        XCTAssertTrue(controller.isRefreshing)
        XCTAssertEqual(controller.demandCount, 1)
        controller.setDemand(.controlCenter, active: true)
        XCTAssertEqual(controller.demandCount, 1)

        controller.setDemand(.controlCenter, active: false)
        XCTAssertFalse(controller.isRefreshing)
        controller.toggleMuteAll()
        XCTAssertEqual(engine.gains.last?.1, 0)
        controller.stop()
    }

    func testPermissionErrorIsReportedAsDenied() {
        let engine = ProcessAudioControllerStub()
        let controller = makeController(engine: engine)
        controller.refreshApplications()
        engine.error = ProcessAudioEngineError.tapCreationFailed(kAudioDevicePermissionsError)

        controller.setVolume(50, for: controller.applications[0])

        XCTAssertEqual(controller.permissionState, .denied)
        controller.stop()
    }

    func testStoredGainRestoreDiscoveryChangeAndFailureCallbackRemainVisible() async {
        let suite = "AudioMixerRestoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(["com.apple.Safari": 35.0], forKey: "audioMixer.applicationGains.v1")
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let discovery = AudioDiscoveryStub(discovered: [makeApplication()])
        let engine = ProcessAudioControllerStub()
        let bridge = BrowserAudioBridgeStub()
        let controller = AudioMixerController(
            discovery: discovery,
            engine: engine,
            browserBridge: bridge,
            defaults: defaults
        )

        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(engine.gains.last?.0, "com.apple.Safari")
        XCTAssertEqual(engine.gains.last?.1, 0.35)
        XCTAssertEqual(controller.permissionState, .ready)

        discovery.discovered = [makeApplication(processObjectIDs: [42, 43])]
        discovery.fireChange()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.applications.first?.processObjectIDs, [42, 43])
        XCTAssertEqual(engine.gains.last?.1, 0.35)

        engine.fail(bundleID: "com.apple.Safari", error: AudioTestError.failed)
        XCTAssertEqual(controller.permissionState, .failed("Audio pipeline failed"))
        XCTAssertEqual(controller.applications.first?.controlState, .failed("Audio pipeline failed"))

        controller.startRefreshing()
        XCTAssertTrue(controller.isRefreshing)
        controller.stopRefreshing()
        XCTAssertTrue(controller.isRefreshing)
        controller.setDemand(.activePipeline, active: false)
        XCTAssertFalse(controller.isRefreshing)
        controller.stop()
        XCTAssertEqual(bridge.stopCount, 1)
        XCTAssertEqual(engine.stopAllCount, 1)
    }

    func testMuteResetAndBrowserMasterMatrix() {
        let engine = ProcessAudioControllerStub()
        let bridge = BrowserAudioBridgeStub()
        let controller = makeController(engine: engine, bridge: bridge)
        controller.refreshApplications()
        let application = controller.applications[0]

        controller.setVolume(60, for: application)
        controller.toggleMute(controller.applications[0])
        XCTAssertEqual(controller.applications[0].volume, 0)
        controller.toggleMute(controller.applications[0])
        XCTAssertEqual(controller.applications[0].volume, 60)

        let safariTab = BrowserAudioTab(
            id: "safari:1",
            browser: "Safari",
            title: "Safari media",
            canSetVolume: true,
            volume: 40,
            isMuted: false
        )
        let braveTab = BrowserAudioTab(
            id: "chromium:brave:2",
            browser: "Brave",
            title: "Brave media",
            canSetVolume: true,
            volume: 25,
            isMuted: false
        )
        let unknownTab = BrowserAudioTab(
            id: "chromium:chrome:3",
            browser: "Unknown",
            title: "Unknown browser",
            canSetVolume: true,
            volume: 80,
            isMuted: false
        )
        bridge.tabsDidChange?([safariTab, braveTab, unknownTab])

        controller.toggleMute(safariTab)
        XCTAssertEqual(controller.browserTabs[0].volume, 0)
        controller.toggleMute(controller.browserTabs[0])
        XCTAssertEqual(controller.browserTabs[0].volume, 40)
        XCTAssertEqual(controller.effectiveVolume(for: safariTab), 24)
        XCTAssertEqual(controller.effectiveVolume(for: braveTab), 25)
        XCTAssertEqual(controller.effectiveVolume(for: unknownTab), 80)

        controller.toggleMuteAll()
        XCTAssertTrue(controller.applications[0].isMuted)
        XCTAssertTrue(controller.browserTabs.allSatisfy(\.isMuted))
        controller.toggleMuteAll()
        XCTAssertFalse(controller.applications[0].isMuted)
        XCTAssertFalse(controller.browserTabs.allSatisfy(\.isMuted))

        controller.resetAll()
        XCTAssertTrue(controller.applications.allSatisfy { $0.volume == 100 })
        XCTAssertTrue(controller.browserTabs.allSatisfy { $0.volume == 100 })
        controller.stop()
    }

    func testExtensionInstallAndSafariSettingsExposeSuccessAndFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AudioMixerExtensionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = AudioMixerWorkspaceSpy()
        let installer = BrowserExtensionInstaller(
            supportRoot: root,
            resourceBundle: .main,
            workspace: workspace
        )
        var openedSafariIdentifier: String?
        let controller = AudioMixerController(
            discovery: AudioDiscoveryStub(discovered: []),
            engine: ProcessAudioControllerStub(),
            browserBridge: BrowserAudioBridgeStub(),
            extensionInstaller: installer,
            safariPreferencesOpener: { identifier, completion in
                openedSafariIdentifier = identifier
                completion(nil)
            },
            defaults: UserDefaults(suiteName: "AudioMixerExtensionTests-\(UUID().uuidString)")!
        )

        controller.installChromiumExtension()
        XCTAssertTrue(controller.extensionMessage?.contains("Extension files are ready") == true)
        XCTAssertEqual(workspace.revealed.count, 1)
        controller.openSafariExtensionSettings()
        await Task.yield()
        XCTAssertEqual(openedSafariIdentifier, "com.brgirgin.ClipboardHistory.SafariExtension")
        XCTAssertTrue(controller.extensionMessage?.contains("Enable ClipboardHistory Safari Audio") == true)
        controller.stop()

        let failingController = AudioMixerController(
            discovery: AudioDiscoveryStub(discovered: []),
            engine: ProcessAudioControllerStub(),
            browserBridge: BrowserAudioBridgeStub(),
            extensionInstaller: BrowserExtensionInstaller(
                supportRoot: root,
                resourceBundle: .main,
                helperURL: root.appending(path: "missing-helper")
            ),
            safariPreferencesOpener: { _, completion in
                completion(AudioTestError.failed)
            },
            defaults: UserDefaults(suiteName: "AudioMixerExtensionFailureTests-\(UUID().uuidString)")!
        )
        failingController.installChromiumExtension()
        XCTAssertFalse(failingController.extensionMessage?.isEmpty == true)
        failingController.openSafariExtensionSettings()
        await Task.yield()
        XCTAssertEqual(failingController.extensionMessage, "Audio pipeline failed")
        failingController.stop()
    }

    private func makeController(
        engine: ProcessAudioControllerStub,
        bridge: BrowserAudioBridgeStub = BrowserAudioBridgeStub(),
        defaults: UserDefaults? = nil
    ) -> AudioMixerController {
        return AudioMixerController(
            discovery: AudioDiscoveryStub(discovered: [makeApplication()]),
            engine: engine,
            browserBridge: bridge,
            defaults: defaults ?? UserDefaults(suiteName: "AudioMixerControllerTests-\(UUID().uuidString)")!
        )
    }

    private func makeApplication(
        processObjectIDs: Set<AudioObjectID> = [42]
    ) -> AudioApplication {
        AudioApplication(
            id: 42,
            processObjectIDs: processObjectIDs,
            processID: 99,
            bundleID: "com.apple.Safari",
            name: "Safari",
            isProducingOutput: true,
            volume: 100,
            isMuted: false,
            controlState: .native
        )
    }
}

@MainActor
private final class AudioMixerWorkspaceSpy: WorkspaceRevealing {
    private(set) var revealed: [[URL]] = []

    func reveal(_ urls: [URL]) {
        revealed.append(urls)
    }
}
