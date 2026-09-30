import Foundation

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func show(section: AppSettingsSection?)
    func close()
    func stop()
}
