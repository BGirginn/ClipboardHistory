import Foundation

protocol AudioProcessDiscovering: Sendable {
    func applications() -> [AudioApplication]
}
