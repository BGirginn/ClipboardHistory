import AppKit
import CoreAudio
import PDFKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardPanelRenderingTests: XCTestCase {
    func testModularShellRendersSupportedWidthsThemesAndLocales() async throws {
        let context = makeContext()
        do {
            for width in [340.0, 380.0, 420.0] {
                try render(
                    AppShellView(model: context.appModel),
                    named: "control-center-\(Int(width))-light-en",
                    colorScheme: .light,
                    locale: Locale(identifier: "en"),
                    width: width
                )
            }
            try render(
                AppShellView(model: context.appModel),
                named: "control-center-380-dark-tr",
                colorScheme: .dark,
                locale: Locale(identifier: "tr"),
                width: 380
            )
            context.appModel.showMenuBarCustomization()
            for width in [340.0, 380.0, 420.0] {
                try render(
                    AppShellView(model: context.appModel),
                    named: "menu-bar-customization-\(Int(width))-dark-tr",
                    colorScheme: .dark,
                    locale: Locale(identifier: "tr"),
                    width: width
                )
            }
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    func testEmptyPanelRendersAtRequestedSize() async {
        let context = makeContext()
        let hostingView = NSHostingView(
            rootView: ClipboardPanelView(viewModel: context.viewModel)
        )

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.width, 380, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, 500, accuracy: 0.5)
        await cleanup(context)
    }

    func testPanelAndProblematicSettingsStatesRender() async throws {
        let context = makeContext()
        do {
            context.viewModel.setPrivateModeEnabled(true)
            try render(
                ClipboardPanelView(viewModel: context.viewModel),
                named: "panel-private-light",
                colorScheme: .light
            )

            let settingsSections = AppSettingsSection.allCases
            for (index, section) in settingsSections.enumerated() {
                for subsection in section.subsections {
                    try render(
                        AppSettingsView(
                            viewModel: context.appModel.settingsFeature,
                            initialSection: section,
                            initialSubsection: subsection
                        )
                        .frame(width: 380, height: 500),
                        named: "settings-\(section.rawValue)-\(subsection.rawValue)",
                        colorScheme: index.isMultiple(of: 2) ? .light : .dark
                    )
                }
            }
            try render(
                AppSettingsView(
                    viewModel: context.appModel.settingsFeature,
                    initialSection: .inputTools,
                    initialSubsection: .inputScrollReverse
                )
                .frame(width: 340, height: 500),
                named: "settings-input-tools-scroll-dark-tr-340",
                colorScheme: .dark,
                locale: Locale(identifier: "tr"),
                width: 340
            )
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    func testStandaloneViewBranchMatrixRenders() async throws {
        let context = makeContext()
        do {
            let png = try makePNG()
            let imageID = UUID()
            let storedImageFilename = await context.storage.storeImage(png, id: imageID)
            let imageFilename = try XCTUnwrap(storedImageFilename)
            let groupID = UUID()
            let storedGroupFilename = await context.storage.storeImage(png, id: groupID, index: 0)
            let groupFilename = try XCTUnwrap(storedGroupFilename)
            let pdf = try makePDF(from: png)
            let pdfID = UUID()
            let storedPDFFilename = await context.storage.storePayload(
                pdf,
                id: pdfID,
                extension: "pdf",
                encrypt: false
            )
            let pdfFilename = try XCTUnwrap(storedPDFFilename)
            let existingFile = context.directory.appending(path: "available.txt")
            try Data("available".utf8).write(to: existingFile)
            let missingFile = context.directory.appending(path: "missing.txt")
            let metadata = ClipboardProtectedMetadata(
                displayTitle: "Metadata title",
                tags: ["tag"],
                extractedText: "recognized",
                qrCodeText: "qr",
                colorHex: "#112233"
            )
            let text = ClipboardItem(
                type: .text,
                text: "First line\nSecond line",
                hash: "render-text",
                lastUsedAt: .now,
                useCount: 2,
                displayTitle: "Text title",
                contentSubtype: .plainText,
                sourceApplicationBundleID: "com.example.source",
                fileSize: 22,
                protectedMetadata: metadata
            )
            let rich = ClipboardItem(
                type: .richText,
                text: "Rich text",
                hash: "render-rich",
                contentSubtype: .rtf
            )
            let image = ClipboardItem(
                id: imageID,
                type: .image,
                imageFilename: imageFilename,
                hash: "render-image",
                displayTitle: "Image title",
                thumbnailFilename: "\(imageID.uuidString.lowercased())-thumb.png",
                contentSubtype: .image,
                imageWidth: 24,
                imageHeight: 16,
                fileSize: Int64(png.count)
            )
            let imageGroup = ClipboardItem(
                id: groupID,
                type: .imageGroup,
                hash: "render-group",
                contentSubtype: .imageGroup,
                assetFilenames: [groupFilename]
            )
            let pdfItem = ClipboardItem(
                id: pdfID,
                type: .pdf,
                hash: "render-pdf",
                contentSubtype: .pdf,
                payloadFilename: pdfFilename,
                pageCount: 1,
                fileSize: Int64(pdf.count)
            )
            let files = ClipboardItem(
                type: .files,
                hash: "render-files",
                contentSubtype: .file,
                fileURLs: [existingFile.path, missingFile.path]
            )
            let filesWithoutURL = ClipboardItem(
                type: .files,
                hash: "render-files-empty",
                contentSubtype: .file
            )
            let sensitiveImage = ClipboardItem(
                type: .image,
                imageFilename: "missing.png",
                hash: "render-sensitive",
                contentSubtype: .image,
                isSensitive: true
            )
            let missingImage = ClipboardItem(
                type: .image,
                imageFilename: "missing.png",
                hash: "render-missing-image",
                contentSubtype: .image
            )

            context.viewModel.items = [text, rich, image, imageGroup, pdfItem, files]
            context.viewModel.collections = [ClipboardCollection(name: "Render Collection")]
            context.viewModel.selectedItemIDs = [text.id, image.id]
            context.viewModel.refreshDisplayedItems()
            context.viewModel.errorMessage = "Keychain unavailable"
            context.viewModel.archiveStatusMessage = "Recovery ready"

            let actions = ClipboardItemActions(
                selectAndCopy: { _ in },
                copy: { _ in },
                paste: { _ in },
                copyAs: { _, _ in },
                pasteAs: { _, _ in },
                togglePin: { _ in },
                toggleSnippet: { _ in },
                moveToCollection: { _, _ in },
                collections: context.viewModel.collections,
                addToPasteStack: { _ in },
                removeFromPasteStack: { _ in },
                pasteStackItemIDs: [text.id],
                dragProvider: { _ in NSItemProvider() },
                showDetails: { _ in },
                reveal: { _ in },
                exportImage: { _, _ in },
                delete: { _ in },
                menuCommandDidRun: {}
            )

            try render(ClipboardBulkActionsView(viewModel: context.viewModel), named: "bulk-actions", colorScheme: .light)
            try render(ClipboardFilteredEmptyStateView(hasSearch: true), named: "empty-search", colorScheme: .dark)
            try render(ClipboardFilteredEmptyStateView(hasSearch: false), named: "empty-filter", colorScheme: .light)
            try render(ClipboardFullPreview(item: image, storage: context.storage), named: "full-image", colorScheme: .dark)
            try render(ClipboardFullPreview(item: pdfItem, storage: context.storage), named: "full-pdf", colorScheme: .light)
            try render(
                ClipboardImageThumbnail(
                    item: image,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService
                ),
                named: "thumbnail-image",
                colorScheme: .light
            )
            try render(
                ClipboardImageThumbnail(
                    item: sensitiveImage,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService
                ),
                named: "thumbnail-sensitive",
                colorScheme: .dark
            )
            try render(
                ClipboardImageThumbnail(
                    item: missingImage,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService
                ),
                named: "thumbnail-missing",
                colorScheme: .light
            )
            for (index, item) in [text, rich, image, imageGroup, pdfItem, files].enumerated() {
                try render(
                    ClipboardItemRowContent(
                        item: item,
                        storage: context.storage,
                        thumbnailService: context.viewModel.thumbnailService
                    ),
                    named: "row-content-\(index)",
                    colorScheme: index.isMultiple(of: 2) ? .dark : .light
                )
            }
            try render(
                ClipboardStorageRecoveryView(viewModel: context.appModel.settingsFeature),
                named: "storage-recovery",
                colorScheme: .dark
            )
            try render(
                DocumentClipboardItemRow(
                    item: filesWithoutURL,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService
                ),
                named: "document-no-url",
                colorScheme: .light
            )
            try render(FileDetailPreview(item: files), named: "file-detail", colorScheme: .dark)
            try render(
                ImageClipboardItemRow(
                    item: imageGroup,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService
                ),
                named: "image-group-row",
                colorScheme: .light
            )
            try render(ClipboardDetailView(item: text, viewModel: context.viewModel), named: "detail-text", colorScheme: .dark)
            try render(ClipboardDetailView(item: sensitiveImage, viewModel: context.viewModel), named: "detail-sensitive", colorScheme: .light)
            try render(ClipboardDetailView(item: image, viewModel: context.viewModel), named: "detail-image", colorScheme: .dark)
            try render(ClipboardDetailView(item: pdfItem, viewModel: context.viewModel), named: "detail-pdf", colorScheme: .light)
            try render(ClipboardDetailView(item: files, viewModel: context.viewModel), named: "detail-files", colorScheme: .dark)
            context.viewModel.pasteStackItemIDs = [text.id, rich.id]
            try render(ClipboardPasteStackView(viewModel: context.viewModel), named: "paste-stack-fifo", colorScheme: .light)
            context.viewModel.settings.pasteStackOrder = .lifo
            try render(ClipboardPasteStackView(viewModel: context.viewModel), named: "paste-stack-lifo", colorScheme: .dark)
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: false,
                    pinnedItems: [text],
                    recentItems: [rich, image, files],
                    selectedItemID: text.id,
                    selectedItemIDs: [text.id, rich.id],
                    copiedItemID: text.id,
                    hasSearch: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: true
                ),
                named: "history-list-sections",
                colorScheme: .light
            )
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: true,
                    pinnedItems: [],
                    recentItems: [],
                    selectedItemID: nil,
                    selectedItemIDs: [],
                    copiedItemID: nil,
                    hasSearch: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: false
                ),
                named: "history-list-empty",
                colorScheme: .dark
            )
            try render(
                ClipboardHistoryListView(
                    isHistoryEmpty: false,
                    pinnedItems: [],
                    recentItems: [],
                    selectedItemID: nil,
                    selectedItemIDs: [],
                    copiedItemID: nil,
                    hasSearch: true,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions,
                    reduceMotion: false
                ),
                named: "history-list-filtered-empty",
                colorScheme: .light
            )
            try render(
                ClipboardItemRow(
                    item: text,
                    isSelected: true,
                    isCopied: true,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions
                ),
                named: "item-row-selected-copied",
                colorScheme: .dark
            )
            var pinned = text
            pinned.isPinned = true
            pinned.isEncrypted = true
            try render(
                ClipboardItemRow(
                    item: pinned,
                    isSelected: false,
                    isCopied: false,
                    storage: context.storage,
                    thumbnailService: context.viewModel.thumbnailService,
                    actions: actions
                ),
                named: "item-row-pinned",
                colorScheme: .light
            )
            try render(
                ClipboardItemContextMenu(item: image, actions: actions),
                named: "item-context-menu-image",
                colorScheme: .dark
            )
            try render(
                ClipboardItemContextMenu(item: text, actions: actions),
                named: "item-context-menu-text",
                colorScheme: .light
            )

            context.viewModel.detailItem = text
            try render(ClipboardPanelView(viewModel: context.viewModel), named: "panel-detail", colorScheme: .dark)
            context.viewModel.detailItem = nil
            context.appModel.router.openSettings()
            try render(AppShellView(model: context.appModel), named: "panel-settings", colorScheme: .light)
            context.appModel.router.closeSettings()
            context.viewModel.isStorageAvailable = false
            try render(ClipboardPanelView(viewModel: context.viewModel), named: "panel-storage-failure", colorScheme: .dark)
            context.viewModel.isStorageAvailable = true

            try render(
                ClipboardPanelView(viewModel: context.viewModel),
                named: "panel-history-redesign",
                colorScheme: .dark
            )
            try render(
                ClipboardPanelView(viewModel: context.viewModel),
                named: "panel-history-compact-turkish",
                colorScheme: .light,
                locale: Locale(identifier: "tr"),
                width: 340
            )

            let note = Note(
                title: "Rendered note",
                body: "A locally encrypted note body",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
            try await context.storage.upsertNoteThrowing(note)
            await context.appModel.notes.loadIfNeeded()
            context.appModel.notes.showList()
            try render(
                notesView(context),
                named: "notes-list",
                colorScheme: .light
            )
            try render(
                notesView(context),
                named: "notes-list-compact",
                colorScheme: .dark,
                width: 340
            )
            context.appModel.notes.openEditor(for: note)
            try render(
                notesView(context),
                named: "notes-editor",
                colorScheme: .dark
            )
            try render(
                notesView(context),
                named: "notes-editor-compact-turkish",
                colorScheme: .light,
                locale: Locale(identifier: "tr"),
                width: 340
            )
            context.appModel.router.showControlCenter()

            try render(
                KeyboardCleaningView(
                    controller: context.appModel.inputTools.keyboardCleaning,
                    close: {},
                    openSettings: {}
                ),
                named: "keyboard-cleaning-ready",
                colorScheme: .light
            )
            try render(
                ScrollReverseView(
                    controller: context.appModel.inputTools.scrollReversal,
                    close: {},
                    openSettings: {}
                ),
                named: "scroll-reverse-turkish",
                colorScheme: .light,
                locale: Locale(identifier: "tr")
            )
            context.appModel.inputTools.keyboardCleaning.start()
            try render(
                KeyboardCleaningView(
                    controller: context.appModel.inputTools.keyboardCleaning,
                    close: {},
                    openSettings: {}
                ),
                named: "keyboard-cleaning-active",
                colorScheme: .dark
            )
            context.appModel.inputTools.keyboardCleaning.stop()
            context.appModel.inputTools.scrollReversal.isEnabled = true
            try render(
                ScrollReverseView(
                    controller: context.appModel.inputTools.scrollReversal,
                    close: {},
                    openSettings: {}
                ),
                named: "scroll-reverse-active",
                colorScheme: .dark
            )
            context.appModel.inputTools.scrollReversal.disable()
            context.appModel.showKeyboardCleaning()
            try render(
                AppShellView(model: context.appModel),
                named: "panel-input-tools-route",
                colorScheme: .light
            )
            context.appModel.showControlCenter()

            context.viewModel.isPrivateMode = true
            context.viewModel.privateModeUntil = .now.addingTimeInterval(60)
            try render(ClipboardPanelStatusView(viewModel: context.viewModel), named: "status-private", colorScheme: .light)
            context.viewModel.isPrivateMode = false
            context.viewModel.privateModeUntil = nil
            context.viewModel.pauseUntil = .now.addingTimeInterval(60)
            try render(ClipboardPanelStatusView(viewModel: context.viewModel), named: "status-paused", colorScheme: .dark)
            context.viewModel.pauseUntil = nil
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    func testSystemMonitorAudioMixerAndStatusBranchMatrixRenders() async throws {
        let context = makeContext()
        do {
            let thermalStates: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
            for (index, thermalState) in thermalStates.enumerated() {
                await context.appModel.systemMetrics.refreshNow()
                try render(
                    SystemMonitorView(
                        controller: context.appModel.systemMetrics,
                        close: {},
                        openSettings: {}
                    ),
                    named: "system-monitor-\(index)-\(thermalState.rawValue)",
                    colorScheme: index.isMultiple(of: 2) ? .light : .dark,
                    locale: index == 3 ? Locale(identifier: "tr") : Locale(identifier: "en"),
                    width: [340.0, 380.0, 420.0, 380.0][index]
                )
            }
            let history = context.appModel.systemMetrics.history
            try render(
                SystemMetricHistoryChart(
                    title: "Dynamic metric history",
                    color: .green,
                    history: history,
                    value: { $0.memory.usedPercent },
                    fixedMaximum: nil
                ),
                named: "system-history-dynamic",
                colorScheme: .light
            )
            try render(
                SystemMetricHistoryChart(
                    title: "Fixed metric history",
                    color: .blue,
                    history: history,
                    value: { $0.cpu.totalPercent },
                    fixedMaximum: 100
                ),
                named: "system-history-fixed",
                colorScheme: .dark
            )
            try render(
                SystemDualMetricHistoryChart(
                    title: "Dual metric history",
                    firstLabel: "Read",
                    secondLabel: "Write",
                    firstColor: .purple,
                    secondColor: .pink,
                    history: history,
                    firstValue: { $0.disk.readBytesPerSecond },
                    secondValue: { $0.disk.writtenBytesPerSecond }
                ),
                named: "system-history-dual",
                colorScheme: .light
            )
            try render(
                TemperatureSensorList(
                    readings: context.appModel.systemMetrics.snapshot.temperatures,
                    statistics: context.appModel.systemMetrics.temperatureStatistics
                ),
                named: "temperature-sensor-statistics",
                colorScheme: .dark
            )

            context.appModel.controlCenter.setMetricGroupVisible(true)
            context.appModel.controlCenter.setMetricsAsSeparateItems(true)
            context.appModel.controlCenter.setMetricStyle(.iconAndValue)
            context.appModel.controlCenter.setMetricFormats(
                MetricFormatPreferences(
                    memory: .usedAndTotal,
                    temperature: .fahrenheit,
                    rate: .megabytes
                )
            )
            try render(
                MenuBarMetricsConfigurationCard(model: context.appModel.controlCenter),
                named: "menu-bar-metrics-visible",
                colorScheme: .dark
            )

            context.appModel.audioMixer.refreshApplications()
            context.audioBridge.publish([])
            try render(
                AudioMixerApplicationSection(
                    applications: [],
                    controller: context.appModel.audioMixer
                ),
                named: "audio-applications-empty",
                colorScheme: .dark
            )
            try render(
                AudioMixerView(
                    controller: context.appModel.audioMixer,
                    close: {},
                    openSettings: {}
                ),
                named: "audio-mixer-empty-tabs",
                colorScheme: .light,
                width: 340
            )

            let tabs = [
                BrowserAudioTab(
                    id: "safari:42",
                    browser: "Safari",
                    title: "Accessible HTML Media",
                    canSetVolume: true,
                    volume: 50,
                    isMuted: false
                ),
                BrowserAudioTab(
                    id: "chromium:brave:7",
                    browser: "Brave",
                    title: "Authorized Chromium Tab",
                    canSetVolume: true,
                    volume: 0,
                    isMuted: true
                )
            ]
            context.audioBridge.publish(tabs)
            let safari = try XCTUnwrap(
                context.appModel.audioMixer.applications.first { $0.bundleID == "com.apple.Safari" }
            )
            context.appModel.audioMixer.setVolume(40, for: safari)
            context.appModel.audioMixer.extensionMessage = "Extension setup guidance"
            try render(
                AudioMixerView(
                    controller: context.appModel.audioMixer,
                    close: {},
                    openSettings: {}
                ),
                named: "audio-mixer-populated-turkish",
                colorScheme: .dark,
                locale: Locale(identifier: "tr"),
                width: 420
            )

            var failedApplication = safari
            failedApplication.controlState = .failed("Pipeline unavailable")
            try render(
                AudioApplicationRow(
                    application: failedApplication,
                    setVolume: { _ in },
                    toggleMute: {}
                ),
                named: "audio-application-failed",
                colorScheme: .light
            )
            try render(
                BrowserAudioTabRow(
                    tab: tabs[0],
                    effectiveVolume: 20,
                    setVolume: { _ in },
                    toggleMute: {},
                    activate: {}
                ),
                named: "browser-tab-effective-volume",
                colorScheme: .dark
            )

            context.appModel.notes.openQuickEditor()
            for (index, state) in [
                NoteController.SaveState.idle,
                .saving,
                .saved,
                .failed
            ].enumerated() {
                context.appModel.notes.saveState = state
                context.appModel.notes.errorMessage = state == .failed ? "Save unavailable" : nil
                try render(
                    NoteEditorStatusView(
                        controller: context.appModel.notes,
                        beginModalInteraction: {},
                        endModalInteraction: {},
                        menuCommandDidRun: {}
                    ),
                    named: "note-status-\(index)",
                    colorScheme: index.isMultiple(of: 2) ? .light : .dark
                )
            }
            context.appModel.notes.saveState = .failed
            context.appModel.notes.errorMessage = nil
            try render(
                NoteEditorStatusView(
                    controller: context.appModel.notes,
                    beginModalInteraction: {},
                    endModalInteraction: {},
                    menuCommandDidRun: {}
                ),
                named: "note-status-failed-without-message",
                colorScheme: .light
            )

            try render(
                ClipboardHeaderActionButton(
                    title: "Active Header Action",
                    systemImage: "bolt.fill",
                    helpText: "Active action",
                    accessibilityIdentifier: "coverage.header.active",
                    accessibilityValue: "Active",
                    isActive: true,
                    tint: .orange,
                    action: {}
                ),
                named: "clipboard-header-action-active",
                colorScheme: .dark
            )
            try render(
                ClipboardHeaderActionButton(
                    title: "Disabled Header Action",
                    systemImage: "bolt",
                    helpText: "Disabled action",
                    accessibilityIdentifier: "coverage.header.disabled",
                    accessibilityValue: "Disabled",
                    isDisabled: true,
                    action: {}
                ),
                named: "clipboard-header-action-disabled",
                colorScheme: .light
            )

            let keyboard = context.appModel.inputTools.keyboardCleaning
            keyboard.stop()
            context.inputCoordinator.trusted = false
            context.inputCoordinator.requestResult = false
            keyboard.start()
            try render(
                KeyboardCleaningAvailabilityView(controller: keyboard),
                named: "keyboard-cleaning-permission",
                colorScheme: .light
            )
            context.inputCoordinator.trusted = true
            context.inputCoordinator.keyboardResult = false
            keyboard.retryAfterPermissionChange()
            try render(
                KeyboardCleaningAvailabilityView(controller: keyboard),
                named: "keyboard-cleaning-error",
                colorScheme: .dark
            )

            let scroll = context.appModel.inputTools.scrollReversal
            context.inputCoordinator.trusted = false
            scroll.isEnabled = true
            try render(
                ScrollReversalStatusView(controller: scroll),
                named: "scroll-reversal-permission",
                colorScheme: .light
            )
            context.inputCoordinator.trusted = true
            context.inputCoordinator.scrollResult = false
            scroll.retryAfterPermissionChange()
            try render(
                ScrollReversalStatusView(controller: scroll),
                named: "scroll-reversal-error",
                colorScheme: .dark
            )
            context.inputCoordinator.scrollResult = true
            scroll.retryAfterPermissionChange()
            try render(
                ScrollReversalStatusView(controller: scroll),
                named: "scroll-reversal-active-status",
                colorScheme: .light
            )
            scroll.disable()
            try render(
                ScrollReversalStatusView(controller: scroll),
                named: "scroll-reversal-inactive-status",
                colorScheme: .dark
            )
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    private func render<Content: View>(
        _ content: Content,
        named name: String,
        colorScheme: ColorScheme,
        locale: Locale = Locale(identifier: "en"),
        width: CGFloat = 380,
        height: CGFloat = 500
    ) throws {
        let hostingView = NSHostingView(
            rootView: content
                .environment(\.colorScheme, colorScheme)
                .environment(\.locale, locale)
        )
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        XCTAssertEqual(representation.pixelsWide, Int((width * 2).rounded()), accuracy: 2)
        XCTAssertEqual(representation.pixelsHigh, Int((height * 2).rounded()), accuracy: 2)

        let outputDirectory = ProcessInfo.processInfo.environment[
            "CLIPBOARD_HISTORY_RENDER_OUTPUT"
        ] ?? "/tmp/ClipboardHistoryUI"
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let png = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        try png.write(
            to: directory.appending(path: "\(name).png"),
            options: .atomic
        )
    }

    private func notesView(_ context: Context) -> NotesContainerView {
        NotesContainerView(
            controller: context.appModel.notes,
            closeToHome: {},
            openSettings: {},
            beginModalInteraction: {},
            endModalInteraction: {},
            menuCommandDidRun: {}
        )
    }

    private struct Context {
        let directory: URL
        let defaultsSuite: String
        let storage: StorageService
        let appModel: AppModel
        let viewModel: ClipboardHistoryViewModel
        let audioBridge: RenderingBrowserAudioBridge
        let inputCoordinator: InputEventTapCoordinatorStub
    }

    private func makeContext() -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardPanelRenderingTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let pasteboard = NSPasteboard(
            name: .init("PanelRenderingTests-\(UUID().uuidString)")
        )
        let defaultsSuite = "PanelRenderingDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let storage = StorageService(baseDirectory: directory)
        let inputEventTapCoordinator = InputEventTapCoordinatorStub(isTrusted: true)
        let audioBridge = RenderingBrowserAudioBridge()
        let audioMixer = AudioMixerController(
            discovery: RenderingAudioDiscovery(),
            engine: RenderingAudioEngine(),
            browserBridge: audioBridge,
            defaults: defaults
        )
        let systemMetrics = SystemMetricsController(
            provider: RenderingSystemMetricsProvider(),
            defaults: defaults
        )
        let appModel = AppModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            inputEventTapCoordinator: inputEventTapCoordinator,
            systemMetricsController: systemMetrics,
            audioMixerController: audioMixer,
            controlCenter: ControlCenterModel(
                store: MenuBarConfigurationStore(defaults: defaults)
            ),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            defaultsSuite: defaultsSuite,
            storage: storage,
            appModel: appModel,
            viewModel: appModel.clipboard,
            audioBridge: audioBridge,
            inputCoordinator: inputEventTapCoordinator
        )
    }

    private func cleanup(_ context: Context) async {
        context.appModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }

    private func makePNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 24, height: 16))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 16).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func makePDF(from png: Data) throws -> Data {
        let image = try XCTUnwrap(NSImage(data: png))
        let page = try XCTUnwrap(PDFPage(image: image))
        let document = PDFDocument()
        document.insert(page, at: 0)
        return try XCTUnwrap(document.dataRepresentation())
    }
}

private actor RenderingSystemMetricsProvider: SystemMetricsProviding {
    private var sampleIndex = 0

    func sample(at date: Date) -> SystemMetricSnapshot {
        let pressures: [MemoryPressureLevel] = [.normal, .warning, .critical, .normal]
        let thermalStates: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        let index = min(sampleIndex, pressures.count - 1)
        sampleIndex += 1
        return SystemMetricSnapshot(
            timestamp: date,
            cpu: CPUUsageSnapshot(
                totalPercent: 42 + Double(index),
                userPercent: 28,
                systemPercent: 14,
                idlePercent: 58
            ),
            memory: MemoryUsageSnapshot(
                totalBytes: 16_000_000_000,
                usedBytes: 9_000_000_000,
                activeBytes: 5_000_000_000,
                inactiveBytes: 2_000_000_000,
                wiredBytes: 2_000_000_000,
                compressedBytes: 2_000_000_000,
                cachedBytes: 1_000_000_000,
                freeBytes: 4_000_000_000,
                pressure: pressures[index]
            ),
            network: NetworkRateSnapshot(
                receivedBytesPerSecond: 12_000_000,
                sentBytesPerSecond: 2_500_000,
                interfaceName: index == 3 ? nil : "en0"
            ),
            disk: DiskRateSnapshot(
                readBytesPerSecond: 30_000_000,
                writtenBytesPerSecond: 8_000_000,
                devices: [
                    DiskDeviceRate(
                        id: "disk0",
                        name: "Internal SSD",
                        isExternal: false,
                        readBytesPerSecond: 25_000_000,
                        writtenBytesPerSecond: 6_000_000
                    ),
                    DiskDeviceRate(
                        id: "disk4",
                        name: "External SSD",
                        isExternal: true,
                        readBytesPerSecond: 5_000_000,
                        writtenBytesPerSecond: 2_000_000
                    )
                ]
            ),
            temperatures: [
                TemperatureReading(id: "cpu", name: "CPU Die", celsius: 55 + Double(index)),
                TemperatureReading(id: "soc", name: "SoC Die", celsius: 51 + Double(index))
            ],
            thermalState: thermalStates[index]
        )
    }
}

private struct RenderingAudioDiscovery: AudioProcessDiscovering {
    func applications() -> [AudioApplication] {
        [
            AudioApplication(
                id: 41,
                processObjectIDs: [41, 42],
                processID: 410,
                bundleID: "com.apple.Safari",
                name: "Safari",
                isProducingOutput: true,
                volume: 100,
                isMuted: false,
                controlState: .native
            ),
            AudioApplication(
                id: 51,
                processID: 510,
                bundleID: "com.brave.Browser",
                name: "Brave",
                isProducingOutput: false,
                volume: 100,
                isMuted: false,
                controlState: .native
            )
        ]
    }
}

@MainActor
private final class RenderingAudioEngine: ProcessAudioControlling {
    func setGain(_: Double, for _: Set<AudioObjectID>, bundleID _: String) throws {}
    func stopControlling(bundleID _: String) {}
    func stopAll() {}
}

@MainActor
private final class RenderingBrowserAudioBridge: BrowserAudioBridging {
    var tabsDidChange: (([BrowserAudioTab]) -> Void)?

    func start() {}
    func stop() {}
    func setVolume(_: Double, tabID _: String) {}
    func activate(tabID _: String) {}

    func publish(_ tabs: [BrowserAudioTab]) {
        tabsDidChange?(tabs)
    }
}
