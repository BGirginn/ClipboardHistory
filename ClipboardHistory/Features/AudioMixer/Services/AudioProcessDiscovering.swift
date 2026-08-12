import Foundation

protocol AudioProcessDiscovering: Sendable {
    func applications() -> [AudioApplication]
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void)
    func stopObservingChanges()
}

extension AudioProcessDiscovering {
    func startObservingChanges(_ handler: @escaping @Sendable () -> Void) {}
    func stopObservingChanges() {}
}
