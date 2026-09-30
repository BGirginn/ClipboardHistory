import SwiftUI

struct NoteEditorView: View {
    @ObservedObject var controller: NoteController
    let openSettings: () -> Void
    let beginModalInteraction: () -> Void
    let endModalInteraction: () -> Void
    let menuCommandDidRun: () -> Void
    @FocusState private var bodyIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorToolbarView(
                controller: controller,
                close: closeEditor,
                openSettings: openSettings,
                beginModalInteraction: beginModalInteraction,
                endModalInteraction: endModalInteraction,
                menuCommandDidRun: menuCommandDidRun
            )

            Divider()

            NoteEditorSurfaceView(
                title: $controller.draftTitle,
                bodyText: $controller.draftBody,
                bodyFocus: $bodyIsFocused
            )
            .layoutPriority(1)

            NoteEditorStatusView(
                controller: controller,
                beginModalInteraction: beginModalInteraction,
                endModalInteraction: endModalInteraction,
                menuCommandDidRun: menuCommandDidRun
            )
        }
        .task(id: controller.draftSessionID) {
            await Task.yield()
            bodyIsFocused = true
        }
    }

    private func closeEditor() {
        controller.requestShowList()
    }
}
