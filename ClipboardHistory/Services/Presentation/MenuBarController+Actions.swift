import AppKit
import Foundation

@MainActor
extension MenuBarController {
    func isStatusItemEvent(_ event: NSEvent) -> Bool {
        statusItems.values.contains { event.window === $0.button?.window }
    }

    @objc func handleStatusItemAction(_ sender: NSStatusBarButton) {
        guard let itemID = statusItems.first(where: { $0.value.button === sender })?.key else { return }
        if dependencies.currentEvent()?.type == .rightMouseUp {
            showStatusMenu(for: itemID)
        } else {
            handleLeftClick(on: itemID)
        }
    }

    private func handleLeftClick(on itemID: MenuBarItemID) {
        switch itemID {
        case .controlCenter:
            if isPopoverShown, activeAnchorID == itemID {
                closePopover()
            } else {
                openFeature(.controlCenter, anchorID: itemID)
            }
        case let .feature(id):
            let action: FeatureClickAction = id == .keyboardCleaning
                ? .toggleKeyboardCleaning
                : appModel.controlCenter.configuration(for: id).clickAction
            Task { [weak self] in
                guard let self,
                      await flushNoteIfNeeded(before: id, action: action),
                      let destination = appModel.performStandaloneAction(for: id, action: action) else { return }
                let preservesPreparedRoute = id == .notes
                    && action == .newNote
                if isPopoverShown,
                   activeAnchorID == itemID,
                   appModel.router.activeFeature == destination,
                   !preservesPreparedRoute {
                    closePopover()
                } else {
                    openFeature(
                        destination,
                        anchorID: itemID,
                        preparesDestination: !preservesPreparedRoute
                    )
                }
            }
        case .metricGroup, .metric:
            if isPopoverShown, appModel.router.activeFeature == .systemMonitor {
                closePopover()
            } else {
                openFeature(.systemMonitor, anchorID: itemID)
            }
        }
    }

    private func flushNoteIfNeeded(
        before id: UtilityFeatureID,
        action: FeatureClickAction
    ) async -> Bool {
        guard appModel.router.activeFeature == .notes,
              id != .notes || action == .newNote else { return true }
        return (await appModel.notes.flushPendingSave()).allowsTransition
    }

    private func showStatusMenu(for itemID: MenuBarItemID) {
        guard let button = statusItems[itemID]?.button else { return }
        activeAnchorID = itemID
        if isPopoverShown,
           appModel.router.activeFeature == .notes,
           appModel.notes.hasPendingChanges {
            Task { [weak self, weak button] in
                guard let self, let button else { return }
                let outcome = await appModel.notes.flushPendingSave()
                guard outcome.allowsTransition else { return }
                closePopover()
                presentStatusMenu(for: itemID, from: button)
            }
            return
        }
        closePopover()
        presentStatusMenu(for: itemID, from: button)
    }

    private func presentStatusMenu(
        for itemID: MenuBarItemID,
        from button: NSStatusBarButton
    ) {
        let menu = NSMenu()
        switch itemID {
        case .controlCenter:
            menu.addItem(makeMenuItem(
                title: String(localized: "Customize Menu Bar"),
                action: #selector(openMenuBarCustomization),
                systemImage: "slider.horizontal.3"
            ))
        case let .feature(id):
            let descriptor = appModel.controlCenter.registry.descriptor(for: id)
            let openItem = makeMenuItem(
                title: descriptor?.title(for: .open) ?? String(localized: "Open Module"),
                action: #selector(openRepresentedFeature),
                systemImage: "arrow.up.forward.app"
            )
            openItem.representedObject = id.rawValue
            menu.addItem(openItem)
            if descriptor?.supportedClickActions.contains(where: { $0 != .open }) == true {
                let quickItem = makeMenuItem(
                    title: quickActionTitle(for: id),
                    action: #selector(runRepresentedQuickAction)
                )
                quickItem.representedObject = id.rawValue
                quickItem.state = quickActionState(for: id)
                menu.addItem(quickItem)
            }
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(
                title: String(localized: "Customize Menu Bar"),
                action: #selector(openMenuBarCustomization),
                systemImage: "slider.horizontal.3"
            ))
        case .metricGroup, .metric:
            menu.addItem(makeMenuItem(
                title: String(localized: "Open System Monitor"),
                action: #selector(openSystemMonitor),
                systemImage: "gauge.with.dots.needle.67percent"
            ))
            menu.addItem(makeMenuItem(
                title: String(localized: "Customize Menu Bar"),
                action: #selector(openMenuBarCustomization),
                systemImage: "slider.horizontal.3"
            ))
        }
        let settingsItem = makeMenuItem(
            title: String(localized: "Open Settings"),
            action: #selector(openRepresentedSettings),
            systemImage: "gearshape"
        )
        settingsItem.representedObject = settingsSection(for: itemID).rawValue
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(
            title: String(localized: "Quit CoreDeck"),
            action: #selector(quitApplication),
            keyEquivalent: "q",
            systemImage: "power"
        ))
        dependencies.presentStatusMenu(menu, button)
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        systemImage: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func quitApplication() {
        dependencies.terminateApplication()
    }

    @objc private func openMenuBarCustomization() {
        openFeature(.menuBarCustomization, anchorID: activeAnchorID)
    }

    @objc private func openRepresentedSettings(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let section = AppSettingsSection(rawValue: rawValue) else { return }
        openFeature(
            .settings,
            anchorID: activeAnchorID,
            settingsSection: section
        )
    }

    @objc private func openSystemMonitor() {
        openFeature(.systemMonitor, anchorID: activeAnchorID)
    }

    @objc private func openRepresentedFeature(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let id = UtilityFeatureID(rawValue: rawValue) else { return }
        openFeature(appModel.route(for: id), anchorID: .feature(id))
    }

    @objc private func runRepresentedQuickAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let id = UtilityFeatureID(rawValue: rawValue) else { return }
        let quickAction = appModel.controlCenter.registry.descriptor(for: id)?
            .supportedClickActions.first { $0 != .open } ?? .open
        Task { [weak self] in
            guard let self,
                  await flushNoteIfNeeded(before: id, action: quickAction) else { return }
            let destination = appModel.performStandaloneAction(for: id, action: quickAction)
            if let destination {
                let preservesPreparedRoute = id == .notes
                    && quickAction == .newNote
                openFeature(
                    destination,
                    anchorID: .feature(id),
                    preparesDestination: !preservesPreparedRoute
                )
            }
        }
    }

    private func settingsSection(for itemID: MenuBarItemID) -> AppSettingsSection {
        switch itemID {
        case .controlCenter:
            .general
        case let .feature(id):
            switch id {
            case .clipboard:
                .clipboard
            case .systemMonitor:
                .systemMonitor
            case .audioMixer:
                .audioMixer
            case .notes:
                .notes
            case .keyboardCleaning, .scrollReverse:
                .inputTools
            }
        case .metricGroup, .metric:
            .systemMonitor
        }
    }
}
