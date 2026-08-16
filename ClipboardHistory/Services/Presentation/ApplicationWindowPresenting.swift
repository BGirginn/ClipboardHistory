import Foundation

@MainActor
protocol ApplicationWindowPresenting: AnyObject {
    var isWindowVisible: Bool { get }

    func showControlCenter()
    func showActiveFeature()
    func stop()
}
