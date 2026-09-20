import AppKit

@MainActor
extension MenuBarController {
    func rebuildStatusItems(
        configuration: MenuBarConfiguration? = nil,
        keyboardCleaningActive: Bool? = nil,
        scrollReversalActive: Bool? = nil
    ) {
        let configuration = configuration ?? appModel.controlCenter.configuration
        var desired: [MenuBarItemID] = []
        if configuration.showsControlCenterItem { desired.append(.controlCenter) }
        if configuration.showsDrawerItem { desired.append(.drawer) }
        desired.append(contentsOf: configuration.features
            .filter {
                $0.id != .systemMonitor && !$0.placement.showsInDrawer
                    && shouldShowFeatureStatusItem(
                    $0,
                    keyboardCleaningActive: keyboardCleaningActive,
                    scrollReversalActive: scrollReversalActive
                )
            }
            .map { .feature($0.id) })
        if configuration.showsSystemMetricsInMenuBar {
            if configuration.metricGroup.showsSeparateItems {
                desired.append(contentsOf: configuration.visibleMenuBarMetrics.map(MenuBarItemID.metric))
            } else {
                desired.append(.metricGroup)
            }
        }
        appModel.systemMetrics.setDemand(
            configuration.showsSystemMetricsInMenuBar ? .menuBar : nil,
            for: .menuBar
        )
        let removesActiveAnchor = !desired.contains(activeAnchorID)

        let desiredSet = Set(desired)
        for itemID in Array(statusItems.keys) where !desiredSet.contains(itemID) {
            if itemID == .drawer, drawerPopover.isShown {
                drawerPopover.performClose(nil)
            }
            if let item = statusItems.removeValue(forKey: itemID) {
                dependencies.removeStatusItem(item)
            }
            renderedStatusStates.removeValue(forKey: itemID)
            metricStripViews.removeValue(forKey: itemID)?.removeFromSuperview()
        }
        for itemID in desired where statusItems[itemID] == nil {
            let item = dependencies.makeStatusItem()
            item.autosaveName = itemID.autosaveName
            if let button = item.button {
                button.target = self
                button.action = #selector(handleStatusItemAction(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.setAccessibilityIdentifier(itemID.accessibilityIdentifier)
                button.setAccessibilityHelp(
                    String(localized: "Left-click to use this module. Right-click for options.")
                )
            }
            statusItems[itemID] = item
        }
        if statusItems[activeAnchorID] == nil {
            activeAnchorID = statusItems[.controlCenter] != nil
                ? .controlCenter
                : desired.first ?? .controlCenter
        }
        updateStatusIcon(configuration: configuration)
        appModel.controlCenter.setRequestedMenuBarItemsVisible(
            desired.allSatisfy { statusItems[$0]?.isVisible == true }
        )
        reanchorPopoverIfNeeded(removesActiveAnchor: removesActiveAnchor)
    }

    func refreshConditionalStatusItems(
        keyboardCleaningActive: Bool? = nil,
        scrollReversalActive: Bool? = nil
    ) {
        let configuration = appModel.controlCenter.configuration
        let conditionalFeatures = configuration.features.filter {
            $0.id != .systemMonitor && !$0.placement.showsInDrawer
                && $0.placement.menuBarVisibility == .whenActive
        }
        let needsRebuild = conditionalFeatures.contains { feature in
            let isPresent = statusItems[.feature(feature.id)] != nil
            return isPresent != shouldShowFeatureStatusItem(
                feature,
                keyboardCleaningActive: keyboardCleaningActive,
                scrollReversalActive: scrollReversalActive
            )
        }
        if needsRebuild {
            rebuildStatusItems(
                configuration: configuration,
                keyboardCleaningActive: keyboardCleaningActive,
                scrollReversalActive: scrollReversalActive
            )
        } else {
            updateStatusIcon(
                configuration: configuration,
                keyboardCleaningActive: keyboardCleaningActive,
                scrollReversalActive: scrollReversalActive
            )
        }
    }

    private func shouldShowFeatureStatusItem(
        _ feature: UtilityFeatureConfiguration,
        keyboardCleaningActive: Bool? = nil,
        scrollReversalActive: Bool? = nil
    ) -> Bool {
        switch feature.placement.menuBarVisibility {
        case .hidden:
            return false
        case .always:
            return true
        case .whenActive:
            return switch feature.id {
            case .clipboard:
                appModel.clipboard.isPrivateMode || appModel.clipboard.isPaused
            case .keyboardCleaning:
                keyboardCleaningActive ?? appModel.inputTools.keyboardCleaning.isActive
            case .scrollReverse:
                scrollReversalActive ?? appModel.inputTools.scrollReversal.isActive
            case .audioMixer:
                appModel.audioMixer.hasActiveUserIntervention
            case .notes, .systemMonitor:
                false
            }
        }
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

    func updateStatusIcon(
        configuration: MenuBarConfiguration? = nil,
        keyboardCleaningActive: Bool? = nil,
        scrollReversalActive: Bool? = nil
    ) {
        let keyboardCleaningActive = keyboardCleaningActive
            ?? appModel.inputTools.keyboardCleaning.isActive
        let scrollReversalActive = scrollReversalActive
            ?? appModel.inputTools.scrollReversal.isActive
        var activeStates: [String] = []
        if keyboardCleaningActive {
            activeStates.append(String(localized: "Keyboard Cleaning Mode active"))
        }
        if appModel.clipboard.isPrivateMode {
            activeStates.append(String(localized: "Private Mode enabled"))
        } else if appModel.clipboard.isPaused {
            activeStates.append(String(localized: "Recording paused"))
        }
        if scrollReversalActive {
            activeStates.append(String(localized: "Scroll Reverse active"))
        }
        let stateSuffix = activeStates.isEmpty ? "" : " — " + activeStates.joined(separator: ", ")
        configureStatusItem(
            .controlCenter,
            symbol: activeStates.isEmpty ? "square.grid.2x2" : "square.grid.2x2.fill",
            description: String(localized: "CoreDeck"),
            tooltip: String(localized: "CoreDeck") + stateSuffix
        )
        configureStatusItem(
            .drawer,
            symbol: "rectangle.bottomhalf.inset.filled",
            description: String(localized: "Drawer"),
            tooltip: String(localized: "CoreDeck Drawer")
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
        configureStatusItem(
            .feature(.notes),
            symbol: "note.text",
            description: String(localized: "Notes"),
            tooltip: String(localized: "Notes")
        )
        configureStatusItem(
            .feature(.keyboardCleaning),
            symbol: keyboardCleaningActive ? "keyboard.badge.ellipsis.fill" : "keyboard.badge.ellipsis",
            description: String(localized: "Keyboard Cleaning"),
            tooltip: String(localized: "Keyboard Cleaning")
                + (keyboardCleaningActive ? " — " + String(localized: "Active") : "")
        )
        configureStatusItem(
            .feature(.scrollReverse),
            symbol: scrollReversalActive ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle",
            description: String(localized: "Scroll Reverse"),
            tooltip: String(localized: "Scroll Reverse")
                + (scrollReversalActive ? " — " + String(localized: "Active") : "")
        )
        configureStatusItem(
            .feature(.audioMixer),
            symbol: "slider.horizontal.3",
            description: String(localized: "Audio Mixer"),
            tooltip: String(localized: "Audio Mixer")
        )
        updateMetricStatusItems(configuration: configuration)
    }

    func updateMetricStatusItems(
        configuration: MenuBarConfiguration? = nil,
        snapshot: SystemMetricSnapshot? = nil
    ) {
        let configuration = configuration ?? appModel.controlCenter.configuration
        let group = configuration.metricGroup
        guard configuration.showsSystemMetricsInMenuBar else { return }
        let metrics = configuration.visibleMenuBarMetrics
        if group.showsSeparateItems {
            for metric in metrics {
                configureMetricStatusItem(
                    .metric(metric),
                    metrics: [metric],
                    style: group.style,
                    configuration: configuration,
                    snapshot: snapshot
                )
            }
        } else {
            let visibleMetrics = Array(metrics.prefix(group.density.visibleMetricLimit))
            configureMetricStatusItem(
                .metricGroup,
                metrics: visibleMetrics,
                style: group.style,
                configuration: configuration,
                snapshot: snapshot,
                tooltipMetrics: metrics
            )
        }
    }

    private func configureMetricStatusItem(
        _ id: MenuBarItemID,
        metrics: [MenuBarMetricID],
        style: MenuBarMetricStyle,
        configuration: MenuBarConfiguration,
        snapshot: SystemMetricSnapshot?,
        tooltipMetrics: [MenuBarMetricID]? = nil
    ) {
        let formats = configuration.metricFormats
        let parts = metrics.map { metric -> String in
            let value = appModel.systemMetrics.value(
                for: metric,
                snapshot: snapshot,
                formats: formats
            )
            let title = menuBarTitle(for: metric, snapshot: snapshot)
            return style == .compact ? value : "\(title) \(value)"
        }
        let text = parts.joined(separator: "  ")
        let allMetrics = tooltipMetrics ?? metrics
        let tooltip = allMetrics.map {
            metricTooltip(for: $0, snapshot: snapshot, formats: formats)
        }.joined(separator: " · ") + String(localized: " — right-click for options")
        if style == .iconAndValue {
            let segments = metrics.map { metric in
                MenuBarMetricSegmentState(
                    metric: metric,
                    symbol: metric.menuBarSymbol,
                    leadingText: metric.menuBarTextLabel,
                    value: appModel.systemMetrics.value(
                        for: metric,
                        snapshot: snapshot,
                        formats: formats
                    ),
                    accessibilityLabel: metricTooltip(
                        for: metric,
                        snapshot: snapshot,
                        formats: formats
                    ),
                    width: metric.menuBarSegmentWidth(formats: formats)
                )
            }
            applyMetricStripState(
                segments,
                renderedTitle: text,
                tooltip: tooltip,
                to: id
            )
            return
        }
        let metric = metrics.count == 1 ? metrics.first : nil
        let symbol = style == .iconAndValue && metric?.menuBarTextLabel == nil
            ? metric?.systemImage ?? "waveform.path.ecg"
            : nil
        applyRenderedState(
            MenuBarRenderedState(
                title: text,
                symbol: symbol,
                accessibilityDescription: metric.map {
                    menuBarTitle(for: $0, snapshot: snapshot)
                } ?? String(localized: "System Monitor"),
                tooltip: tooltip
            ),
            to: id,
            fixedLength: metrics.count > 1 ? nil : metric?.menuBarStandaloneWidth(formats: formats)
        )
    }

    private func applyMetricStripState(
        _ segments: [MenuBarMetricSegmentState],
        renderedTitle: String,
        tooltip: String,
        to id: MenuBarItemID
    ) {
        guard let item = statusItems[id], let button = item.button else { return }
        let stripView: MenuBarMetricStripView
        if let existing = metricStripViews[id] {
            stripView = existing
        } else {
            stripView = MenuBarMetricStripView(frame: .zero)
            metricStripViews[id] = stripView
            button.addSubview(stripView)
            NSLayoutConstraint.activate([
                stripView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                stripView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }
        stripView.apply(segments)
        let desiredLength = stripView.intrinsicContentSize.width
        if item.length != desiredLength { item.length = desiredLength }
        if !button.title.isEmpty { button.title = "" }
        if button.image != nil { button.image = nil }
        button.imagePosition = .noImage
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        renderedStatusStates[id] = MenuBarRenderedState(
            title: renderedTitle,
            symbol: nil,
            accessibilityDescription: segments.map(\.accessibilityLabel).joined(separator: ", "),
            tooltip: tooltip
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

    private func applyRenderedState(
        _ state: MenuBarRenderedState,
        to id: MenuBarItemID,
        fixedLength: CGFloat? = nil
    ) {
        guard let item = statusItems[id],
              let button = item.button else { return }
        metricStripViews.removeValue(forKey: id)?.removeFromSuperview()
        let desiredLength = state.title.isEmpty
            ? NSStatusItem.squareLength
            : fixedLength ?? NSStatusItem.variableLength
        let previousState = renderedStatusStates[id]
        guard previousState != state || item.length != desiredLength else { return }
        if item.length != desiredLength {
            item.length = desiredLength
        }
        if previousState == nil || previousState?.title.isEmpty != state.title.isEmpty {
            if let cell = button.cell as? NSButtonCell {
                cell.wraps = false
                cell.lineBreakMode = .byClipping
            }
            button.imagePosition = state.title.isEmpty ? .imageOnly : .imageLeading
            button.alignment = state.title.isEmpty ? .center : .left
            if !state.title.isEmpty {
                button.font = metricFont
            }
        }
        if previousState?.title != state.title {
            button.title = state.title
        }
        if previousState?.symbol != state.symbol
            || previousState?.accessibilityDescription != state.accessibilityDescription {
            button.image = state.symbol.flatMap {
                NSImage(
                    systemSymbolName: $0,
                    accessibilityDescription: state.accessibilityDescription
                )
            }
        }
        if previousState?.tooltip != state.tooltip {
            button.toolTip = state.tooltip
            button.setAccessibilityLabel(state.tooltip)
        }

        renderedStatusStates[id] = state
    }

    private var metricFont: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
    }

    private func metricTooltip(
        for metric: MenuBarMetricID,
        snapshot presentedSnapshot: SystemMetricSnapshot?,
        formats: MetricFormatPreferences
    ) -> String {
        let snapshot = presentedSnapshot ?? appModel.systemMetrics.snapshot
        let value = appModel.systemMetrics.value(
            for: metric,
            snapshot: snapshot,
            formats: formats
        )
        let title = menuBarTitle(for: metric, snapshot: snapshot)
        switch metric {
        case .cpu:
            let cpu = snapshot.cpu
            let user = cpu.userPercent.formatted(.number.precision(.fractionLength(0)))
            let system = cpu.systemPercent.formatted(.number.precision(.fractionLength(0)))
            return "\(title): \(value) · \(String(localized: "User")) \(user)% "
                + "· \(String(localized: "System")) \(system)%"
        case .memory:
            let pressure = snapshot.memory.pressure.title
            return "\(title): \(value) · \(pressure)"
        default:
            return "\(title): \(value)"
        }
    }

    private func menuBarTitle(
        for metric: MenuBarMetricID,
        snapshot presentedSnapshot: SystemMetricSnapshot?
    ) -> String {
        if let textLabel = metric.menuBarTextLabel { return textLabel }
        guard metric == .temperature else { return metric.title }
        let snapshot = presentedSnapshot ?? appModel.systemMetrics.snapshot
        guard let source = snapshot.primaryTemperatureReading?.localizedSourceName else {
            return metric.title
        }
        return String(localized: "\(source) Temperature")
    }

}
