import AppKit
import SwiftUI

@MainActor
extension MenuBarController {
    func toggleDrawer() {
        if drawerPopover.isShown {
            drawerPopover.performClose(nil)
            return
        }
        navigationGeneration &+= 1
        let generation = navigationGeneration
        let routeGeneration = appModel.router.navigationGeneration
        Task { [weak self] in
            guard let self else { return }
            if self.isPopoverShown, self.appModel.router.activeFeature == .notes {
                let outcome = await self.appModel.notes.flushPendingSave()
                guard outcome.allowsTransition else { return }
            }
            guard generation == self.navigationGeneration, !self.isStopped,
                  routeGeneration == self.appModel.router.navigationGeneration else { return }
            self.closePopoverNow()
            self.showDrawerNow()
        }
    }

    private func showDrawerNow() {
        guard let anchor = statusItems[.drawer]?.button else { return }
        activeAnchorID = .drawer
        ensureDrawerContent()
        NSApp.activate()
        drawerPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func ensureDrawerContent() {
        guard drawerPopover.contentViewController == nil else { return }
        drawerPopover.contentViewController = NSHostingController(
            rootView: DrawerView(
                model: appModel.controlCenter,
                openFeature: { [weak self] id in
                    guard let self else { return }
                    self.drawerPopover.performClose(nil)
                    self.openFeature(self.appModel.route(for: id), anchorID: .drawer)
                },
                restoreFeature: { [weak self] id in
                    self?.appModel.controlCenter.restoreFeatureToMenuBar(id)
                },
                customize: { [weak self] in
                    guard let self else { return }
                    self.drawerPopover.performClose(nil)
                    self.openFeature(.menuBarCustomization, anchorID: .drawer)
                }
            )
        )
    }
}
