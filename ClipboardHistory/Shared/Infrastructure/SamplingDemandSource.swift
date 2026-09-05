import Foundation

struct SamplingDemandSource: Hashable, Sendable {
    private let id: String

    init(id: String = UUID().uuidString) {
        self.id = id
    }

    static let menuBar = SamplingDemandSource(id: "menu-bar")
    static let activeAudioPipeline = SamplingDemandSource(id: "active-audio-pipeline")
}
