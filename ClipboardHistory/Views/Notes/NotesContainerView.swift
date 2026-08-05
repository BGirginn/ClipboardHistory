import SwiftUI

struct NotesContainerView: View {
    @ObservedObject var viewModel: ClipboardHistoryViewModel
    @ObservedObject private var controller: NoteController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: ClipboardHistoryViewModel) {
        self.viewModel = viewModel
        _controller = ObservedObject(wrappedValue: viewModel.noteController)
    }

    var body: some View {
        NavigationStack(path: $controller.path) {
            NotesListView(controller: controller, close: viewModel.showHistory)
                .navigationDestination(for: NoteController.Route.self) { route in
                    switch route {
                    case .editor:
                        NoteEditorView(controller: controller)
                    }
                }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: controller.path)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("notes.container")
    }
}
