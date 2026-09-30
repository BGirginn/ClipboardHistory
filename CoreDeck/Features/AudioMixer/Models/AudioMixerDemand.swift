import Foundation

enum AudioMixerDemand: Hashable, Sendable {
    case controlCenter
    case detail
    case activePipeline
}
