import AppKit
import SwiftUI

struct AppShellView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var router: AppRouter
    @ObservedObject private var clipboard: ClipboardHistoryViewModel
    @ObservedObject private var notes: NoteController
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var systemMetrics: SystemMetricsController
    @ObservedObject private var audioMixer: AudioMixerController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(model: AppModel) {
        self.model = model
        _router = ObservedObject(wrappedValue: model.router)
        _clipboard = ObservedObject(wrappedValue: model.clipboard)
        _notes = ObservedObject(wrappedValue: model.notes)
        _settings = ObservedObject(wrappedValue: model.settings)
        _systemMetrics = ObservedObject(wrappedValue: model.systemMetrics)
        _audioMixer = ObservedObject(wrappedValue: model.audioMixer)
    }

    var body: some View {
        featureContent
        .frame(
            minWidth: AppDesign.panelMinimumWidth,
            idealWidth: AppDesign.panelIdealWidth,
            maxWidth: AppDesign.panelMaximumWidth,
            minHeight: AppDesign.panelMinimumHeight,
            idealHeight: AppDesign.panelIdealHeight,
            maxHeight: .infinity
        )
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                : AnyShapeStyle(.regularMaterial)
        )
        .background(KeyboardEventMonitorView(handler: handleKeyEvent))
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    @ViewBuilder
    private var featureContent: some View {
        switch router.activeFeature {
        case .controlCenter:
            ControlCenterView(
                controlCenter: model.controlCenter,
                clipboard: clipboard,
                notes: notes,
                keyboardCleaning: model.inputTools.keyboardCleaning,
                scrollReversal: model.inputTools.scrollReversal,
                systemMetrics: systemMetrics,
                audioMixer: audioMixer,
                showFeature: showFeature,
                customizeMenuBar: model.showMenuBarCustomization,
                openSettings: { model.openSettings() }
            )
        case .clipboard:
            ClipboardPanelView(
                viewModel: clipboard,
                backToHome: model.showControlCenter,
                openSettings: { model.openSettings(section: .clipboard) }
            )
        case .notes:
            NotesContainerView(
                controller: notes,
                closeToHome: { model.requestLeaveNotes(to: .controlCenter) },
                openSettings: {
                    model.requestLeaveNotes(to: .settings, settingsSection: .notes)
                },
                beginModalInteraction: { clipboard.beginPanelModalInteraction?() },
                endModalInteraction: { clipboard.endPanelModalInteraction?() },
                menuCommandDidRun: { clipboard.menuCommandDidRun?() }
            )
        case .keyboardCleaning:
            KeyboardCleaningView(
                controller: model.inputTools.keyboardCleaning,
                close: model.showControlCenter,
                openSettings: { model.openSettings(section: .inputTools) }
            )
        case .scrollReverse:
            ScrollReverseView(
                controller: model.inputTools.scrollReversal,
                close: model.showControlCenter,
                openSettings: { model.openSettings(section: .inputTools) }
            )
        case .systemMonitor:
            SystemMonitorView(
                controller: systemMetrics,
                close: model.showControlCenter,
                openSettings: { model.openSettings(section: .systemMonitor) }
            )
        case .audioMixer:
            AudioMixerView(
                controller: audioMixer,
                close: model.showControlCenter,
                openSettings: { model.openSettings(section: .audioMixer) }
            )
        case .menuBarCustomization:
            MenuBarCustomizationView(
                model: model.controlCenter,
                close: model.showControlCenter,
                openSettings: { model.openSettings(section: .menuBar) }
            )
        case .settings:
            AppSettingsView(
                viewModel: model.settingsFeature,
                initialSection: router.settingsSection,
                close: model.closeSettings
            )
        }
    }

    private func showFeature(_ id: UtilityFeatureID) {
        switch id {
        case .clipboard: model.showClipboard()
        case .notes: model.showNoteList()
        case .keyboardCleaning: model.showKeyboardCleaning()
        case .scrollReverse: model.showScrollReverse()
        case .systemMonitor: model.showSystemMonitor()
        case .audioMixer: model.showAudioMixer()
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {
            clipboard.closePanel()
            return true
        }
        if router.activeFeature == .notes, modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n":
                notes.requestNewNote()
                return true
            case "s" where notes.screen == .editor:
                notes.saveImmediately()
                return true
            default:
                return false
            }
        }
        guard router.activeFeature == .clipboard else { return false }
        return ClipboardPanelView(viewModel: clipboard).handleKeyEvent(event)
    }
}
