import Foundation

enum AudioControlState: Equatable, Sendable {
    case native
    case starting
    case controlled
    case failed(String)
}
