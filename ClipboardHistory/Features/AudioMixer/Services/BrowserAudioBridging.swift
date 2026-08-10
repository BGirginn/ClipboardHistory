import Foundation

@MainActor
protocol BrowserAudioBridging: AnyObject {
    var tabsDidChange: (([BrowserAudioTab]) -> Void)? { get set }
    func start()
    func stop()
    func setVolume(_ volume: Double, tabID: String)
    func activate(tabID: String)
}
