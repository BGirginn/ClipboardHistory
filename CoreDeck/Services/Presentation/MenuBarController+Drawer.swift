import AppKit
import SwiftUI

@MainActor
extension MenuBarController {
    func toggleDrawer() {
        if isInlineDrawerExpanded {
            collapseInlineDrawer()
            return
        }
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
        let featureCount = max(appModel.controlCenter.drawerFeatures.count, 1)
        let width = CGFloat(38 + featureCount * 28)
        if dependencies.canPresentInlineDrawer(anchor, width) {
            isInlineDrawerExpanded = true
            refreshInlineDrawer()
        } else {
            ensureDrawerContent()
            NSApp.activate()
            drawerPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    func refreshInlineDrawer() {
        guard isInlineDrawerExpanded,
              let item = statusItems[.drawer],
              let anchor = item.button else { return }
        inlineDrawerButtons?.removeFromSuperview()
        let descriptors = appModel.controlCenter.drawerFeatures
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        if descriptors.isEmpty {
            stack.addArrangedSubview(makeDrawerButton(
                symbol: "slider.horizontal.3",
                title: String(localized: "Customize Menu Bar"),
                identifier: "drawer.customize",
                tag: -1
            ))
        } else {
            for (index, descriptor) in descriptors.enumerated() {
                stack.addArrangedSubview(makeDrawerButton(
                    symbol: descriptor.systemImage,
                    title: descriptor.title,
                    identifier: "drawer.feature.\(descriptor.id.rawValue)",
                    tag: index
                ))
            }
        }
        let width = CGFloat(38 + stack.arrangedSubviews.count * 28)
        item.length = width
        anchor.imagePosition = .imageLeading
        anchor.alignment = .left
        stack.frame = NSRect(x: 34, y: 0, width: width - 36, height: anchor.bounds.height)
        stack.autoresizingMask = [.height]
        anchor.addSubview(stack)
        inlineDrawerButtons = stack
    }

    func collapseInlineDrawer() {
        guard isInlineDrawerExpanded else { return }
        isInlineDrawerExpanded = false
        inlineDrawerButtons?.removeFromSuperview()
        inlineDrawerButtons = nil
        if let item = statusItems[.drawer] {
            item.length = NSStatusItem.squareLength
            item.button?.imagePosition = .imageOnly
            item.button?.alignment = .center
        }
        updateStatusIcon()
    }

    private func makeDrawerButton(symbol: String, title: String, identifier: String, tag: Int) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.target = self
        button.action = #selector(handleInlineDrawerButton(_:))
        button.tag = tag
        button.setFrameSize(NSSize(width: 26, height: 24))
        return button
    }

    @objc private func handleInlineDrawerButton(_ sender: NSButton) {
        if sender.tag == -1 {
            openFeature(.menuBarCustomization, anchorID: .drawer)
            return
        }
        let descriptors = appModel.controlCenter.drawerFeatures
        guard descriptors.indices.contains(sender.tag) else { return }
        openFeature(appModel.route(for: descriptors[sender.tag].id), anchorID: .drawer)
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
