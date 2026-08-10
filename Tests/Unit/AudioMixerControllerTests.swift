import CoreAudio
import XCTest

@testable import ClipboardHistory

private struct AudioDiscoveryStub: AudioProcessDiscovering {
    let discovered: [AudioApplication]
    func applications() -> [AudioApplication] { discovered }
}

@MainActor
private final class ProcessAudioControllerStub: ProcessAudioControlling {
    var gains: [(String, Double)] = []
    var error: Error?
    func setGain(_ gain: Double, for processObjectID: AudioObjectID, bundleID: String) throws {
        if let error { throw error }
        gains.append((bundleID, gain))
    }
    func stopControlling(bundleID: String) {}
    func stopAll() {}
}

@MainActor
private final class BrowserAudioBridgeStub: BrowserAudioBridging {
    var tabsDidChange: (([BrowserAudioTab]) -> Void)?
    var volumes: [(String, Double)] = []
    var activatedIDs: [String] = []
    func start() {}
    func stop() {}
    func setVolume(_ volume: Double, tabID: String) { volumes.append((tabID, volume)) }
    func activate(tabID: String) { activatedIDs.append(tabID) }
}

private enum AudioTestError: LocalizedError {
    case failed
    var errorDescription: String? { "Audio pipeline failed" }
}

@MainActor
final class AudioMixerControllerTests: XCTestCase {
    func testBrowserBridgeMergesSourcesRejectsUncontrollableTabsAndNamespacesCommands() throws {
        let bridge = BrowserAudioBridge()
        var observed: [BrowserAudioTab] = []
        bridge.tabsDidChange = { observed = $0 }
        let chromium = """
        {"version":1,"type":"state","source":"chromium","tabs":[
          {"id":"chromium:4","browser":"Chrome","title":"Music","canSetVolume":true,"volume":100,"isMuted":false},
          {"id":"chromium:5","browser":"Chrome","title":"Protected","canSetVolume":false,"volume":100,"isMuted":false}
        ]}
        """
        let safari = """
        {"version":1,"type":"state","source":"safari","tabs":[
          {"id":"safari:4","browser":"Safari","title":"Video","canSetVolume":true,"volume":80,"isMuted":false}
        ]}
        """

        bridge.handle(requestID: UUID().uuidString, payload: chromium)
        bridge.handle(requestID: UUID().uuidString, payload: safari)

        XCTAssertEqual(Set(observed.map(\.id)), Set(["chromium:4", "safari:4"]))
        bridge.setVolume(25, tabID: "safari:4")
        bridge.handle(requestID: UUID().uuidString, payload: safari)
        XCTAssertEqual(observed.first { $0.id == "safari:4" }?.volume, 25)

        bridge.handle(requestID: UUID().uuidString, payload: "{\"version\":2,\"type\":\"state\",\"tabs\":[]}")
        XCTAssertEqual(Set(observed.map(\.id)), Set(["chromium:4", "safari:4"]))
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

    private func makeController(
        engine: ProcessAudioControllerStub,
        bridge: BrowserAudioBridgeStub = BrowserAudioBridgeStub(),
        defaults: UserDefaults? = nil
    ) -> AudioMixerController {
        let application = AudioApplication(
            id: 42,
            processID: 99,
            bundleID: "com.apple.Safari",
            name: "Safari",
            isProducingOutput: true,
            volume: 100,
            isMuted: false,
            controlState: .native
        )
        return AudioMixerController(
            discovery: AudioDiscoveryStub(discovered: [application]),
            engine: engine,
            browserBridge: bridge,
            defaults: defaults ?? UserDefaults(suiteName: "AudioMixerControllerTests-\(UUID().uuidString)")!
        )
    }
}
