import AppKit

@MainActor
extension MenuBarController {
    func rebuildStatusItems(configuration: MenuBarConfiguration? = nil) {
        let configuration = configuration ?? appModel.controlCenter.configuration
        var desired: Set<MenuBarItemID> = []
        if configuration.showsControlCenterItem { desired.insert(.controlCenter) }
        configuration.features
            .filter { $0.placement.showsStandaloneItem }
            .forEach { desired.insert(.feature($0.id)) }
        if configuration.metricGroup.isVisible && !configuration.metricGroup.metrics.isEmpty {
            if configuration.metricGroup.showsSeparateItems {
                configuration.metricGroup.metrics.forEach { desired.insert(.metric($0)) }
            } else {
                desired.insert(.metricGroup)
            }
        }
        appModel.systemMetrics.setDemand(
            .menuBar,
            active: configuration.metricGroup.isVisible && !configuration.metricGroup.metrics.isEmpty
        )
        let removesActiveAnchor = !desired.contains(activeAnchorID)

        for itemID in Array(statusItems.keys) where !desired.contains(itemID) {
            if let item = statusItems.removeValue(forKey: itemID) {
                dependencies.removeStatusItem(item)
            }
            renderedStatusStates.removeValue(forKey: itemID)
        }
        for itemID in desired where statusItems[itemID] == nil {
            let item = dependencies.makeStatusItem()
            item.autosaveName = itemID.autosaveName
            if let button = item.button {
                button.target = self
                button.action = #selector(handleStatusItemAction(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.setAccessibilityHelp(
                    String(localized: "Left-click to use this module. Right-click for options.")
                )
            }
            statusItems[itemID] = item
        }
        if statusItems[activeAnchorID] == nil {
            activeAnchorID = statusItems[.controlCenter] != nil
                ? .controlCenter
                : statusItems.keys.first ?? .controlCenter
        }
        updateStatusIcon()
        reanchorPopoverIfNeeded(removesActiveAnchor: removesActiveAnchor)
    }

    func quickActionTitle(for id: UtilityFeatureID) -> String {
        switch id {
        case .clipboard:
            appModel.clipboard.isPaused
                ? String(localized: "Resume Recording")
                : String(localized: "Pause Recording for 60 Minutes")
        case .notes: String(localized: "New Note")
        case .keyboardCleaning:
            appModel.inputTools.keyboardCleaning.isActive
                ? String(localized: "Stop Keyboard Cleaning")
                : String(localized: "Start Keyboard Cleaning")
        case .scrollReverse:
            appModel.inputTools.scrollReversal.isEnabled
                ? String(localized: "Disable Scroll Reverse")
                : String(localized: "Enable Scroll Reverse")
        case .systemMonitor: String(localized: "Open System Monitor")
        case .audioMixer:
            appModel.audioMixer.isEverythingMuted
                ? String(localized: "Restore Audio")
                : String(localized: "Mute All Audio")
        }
    }

    func quickActionState(for id: UtilityFeatureID) -> NSControl.StateValue {
        switch id {
        case .clipboard: appModel.clipboard.isPaused ? .on : .off
        case .notes: .off
        case .keyboardCleaning: appModel.inputTools.keyboardCleaning.isActive ? .on : .off
        case .scrollReverse: appModel.inputTools.scrollReversal.isActive ? .on : .off
        case .systemMonitor: .off
        case .audioMixer: appModel.audioMixer.isEverythingMuted ? .on : .off
        }
    }

    func updateStatusIcon() {
        var activeStates: [String] = []
        if appModel.inputTools.keyboardCleaning.isActive {
            activeStates.append(String(localized: "Keyboard Cleaning Mode active"))
        }
        if appModel.clipboard.isPrivateMode {
            activeStates.append(String(localized: "Private Mode enabled"))
        } else if appModel.clipboard.isPaused {
            activeStates.append(String(localized: "Recording paused"))
        }
        if appModel.inputTools.scrollReversal.isActive {
            activeStates.append(String(localized: "Scroll Reverse active"))
        }
        let stateSuffix = activeStates.isEmpty ? "" : " — " + activeStates.joined(separator: ", ")
        configureStatusItem(
            .controlCenter,
            symbol: activeStates.isEmpty ? "square.grid.2x2" : "square.grid.2x2.fill",
            description: String(localized: "ClipboardHistory Control Center"),
            tooltip: String(localized: "ClipboardHistory Control Center") + stateSuffix
        )
        configureStatusItem(
            .feature(.clipboard),
            symbol: appModel.clipboard.isPaused || appModel.clipboard.isPrivateMode
                ? "eye.slash.fill"
                : "clipboard",
            description: String(localized: "Clipboard"),
            tooltip: String(localized: "Clipboard")
                + (appModel.clipboard.isPaused ? " — " + String(localized: "Recording paused") : "")
        )
        configureStatusItem(.feature(.notes), symbol: "note.text", description: String(localized: "Notes"), tooltip: String(localized: "Notes"))
        configureStatusItem(
            .feature(.keyboardCleaning),
            symbol: appModel.inputTools.keyboardCleaning.isActive ? "keyboard.badge.ellipsis.fill" : "keyboard.badge.ellipsis",
            description: String(localized: "Keyboard Cleaning"),
            tooltip: String(localized: "Keyboard Cleaning") + (appModel.inputTools.keyboardCleaning.isActive ? " — " + String(localized: "Active") : "")
        )
        configureStatusItem(
            .feature(.scrollReverse),
            symbol: appModel.inputTools.scrollReversal.isActive ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle",
            description: String(localized: "Scroll Reverse"),
            tooltip: String(localized: "Scroll Reverse") + (appModel.inputTools.scrollReversal.isActive ? " — " + String(localized: "Active") : "")
        )
        configureStatusItem(.feature(.systemMonitor), symbol: "gauge.with.dots.needle.67percent", description: String(localized: "System Monitor"), tooltip: systemMetricsTooltip)
        configureStatusItem(
            .feature(.audioMixer),
            symbol: appModel.audioMixer.isEverythingMuted ? "speaker.slash.fill" : "slider.horizontal.3",
            description: String(localized: "Audio Mixer"),
            tooltip: String(localized: "Audio Mixer")
        )
        configureMetricItems()
    }

    private var systemMetricsTooltip: String {
        let metrics = appModel.systemMetrics
        let formats = appModel.controlCenter.configuration.metricFormats
        return "CPU \(metrics.value(for: .cpu, formats: formats)) · RAM \(metrics.value(for: .memory, formats: formats)) · \(metrics.value(for: .temperature, formats: formats))"
    }

    private func configureMetricItems() {
        let group = appModel.controlCenter.configuration.metricGroup
        guard group.isVisible else { return }
        if group.showsSeparateItems {
            for metric in group.metrics {
                configureMetricStatusItem(.metric(metric), metrics: [metric], style: group.style)
            }
        } else {
            configureMetricStatusItem(.metricGroup, metrics: group.metrics, style: group.style)
        }
    }

    private func configureMetricStatusItem(_ id: MenuBarItemID, metrics: [MenuBarMetricID], style: MenuBarMetricStyle) {
        let formats = appModel.controlCenter.configuration.metricFormats
        let text = metrics.map { metric -> String in
            let value = appModel.systemMetrics.value(for: metric, formats: formats)
            return style == .compact ? value : "\(metric.title) \(value)"
        }.joined(separator: "  ")
        let tooltip = metrics.map {
            "\($0.title): \(appModel.systemMetrics.value(for: $0, formats: formats))"
        }.joined(separator: " · ") + String(localized: " — right-click for options")
        let metric = style == .iconAndValue && metrics.count == 1 ? metrics.first : nil
        applyRenderedState(
            MenuBarRenderedState(
                title: text,
                symbol: metric?.systemImage,
                accessibilityDescription: metric?.title ?? tooltip,
                tooltip: tooltip
            ),
            to: id
        )
    }

    private func configureStatusItem(_ id: MenuBarItemID, symbol: String, description: String, tooltip: String) {
        applyRenderedState(
            MenuBarRenderedState(
                title: "",
                symbol: symbol,
                accessibilityDescription: description,
                tooltip: tooltip + String(localized: " — right-click for options")
            ),
            to: id
        )
    }

    private func applyRenderedState(_ state: MenuBarRenderedState, to id: MenuBarItemID) {
        guard let item = statusItems[id],
              let button = item.button else { return }
        let desiredLength = state.title.isEmpty
            ? NSStatusItem.squareLength
            : NSStatusItem.variableLength
        if item.length != desiredLength {
            item.length = desiredLength
        }
        if let cell = button.cell as? NSButtonCell {
            cell.wraps = false
            cell.lineBreakMode = .byClipping
        }
        button.imagePosition = state.title.isEmpty ? .imageOnly : .imageLeading

        guard renderedStatusStates[id] != state else { return }
        renderedStatusStates[id] = state
        button.title = state.title
        button.image = state.symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: state.accessibilityDescription)
        }
        button.toolTip = state.tooltip
        button.setAccessibilityLabel(state.tooltip)
    }
}
