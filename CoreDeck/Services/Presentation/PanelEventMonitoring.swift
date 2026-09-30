import AppKit

@MainActor
protocol PanelEventMonitoring: AnyObject {
    func addGlobalMonitor(handler: @escaping (NSEvent) -> Void) -> Any?
    func addLocalMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any?
    func removeMonitor(_ monitor: Any)
}
