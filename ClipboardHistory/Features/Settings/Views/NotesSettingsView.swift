import SwiftUI

struct NotesSettingsView: View {
    @ObservedObject var viewModel: SettingsFeatureModel
    @ObservedObject private var notes: NoteController
    let selectedSubsection: AppSettingsSubsection

    init(
        viewModel: SettingsFeatureModel,
        selectedSubsection: AppSettingsSubsection = .notesGeneral
    ) {
        self.viewModel = viewModel
        self.selectedSubsection = selectedSubsection
        _notes = ObservedObject(wrappedValue: viewModel.notes)
    }

    var body: some View {
        Form {
            if selectedSubsection == .notesGeneral {
                Section("Notes") {
                    LabeledContent(
                        "Stored Notes",
                        value: notes.notes.count.formatted()
                    )
                }
            }
            if selectedSubsection == .notesSecurity {
                Section("Security") {
                    Label(
                        "Note titles and bodies are encrypted in local storage.",
                        systemImage: "lock.shield"
                    )
                }
            }
            if selectedSubsection == .notesSaving {
                Section("Saving") {
                    Label(
                        "Changes are saved automatically while editing.",
                        systemImage: "checkmark.circle"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .task { await notes.loadIfNeeded() }
        .accessibilityIdentifier("settings.notes")
    }
}
