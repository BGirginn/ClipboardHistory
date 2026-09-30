import AppKit

@MainActor
protocol DrawerItemImageProviding {
    func image(for id: ManagedMenuBarItemID) async -> NSImage?
}
