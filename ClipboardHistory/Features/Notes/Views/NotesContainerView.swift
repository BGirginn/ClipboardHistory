import SwiftUI

struct NotesContainerView: View {
    @ObservedObject var controller: NoteController
    let closeToHome: () -> Void
    let openSettings: () -> Void
    let beginModalInteraction: () -> Void
    let endModalInteraction: () -> Void
    let menuCommandDidRun: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch controller.screen {
            case .list:
                NotesListView(
                    controller: controller,
                    close: closeToHome,
                    openSettings: openSettings
                )
            case .editor:
                NoteEditorView(
                    controller: controller,
                    openSettings: openSettings,
                    beginModalInteraction: beginModalInteraction,
                    endModalInteraction: endModalInteraction,
                    menuCommandDidRun: menuCommandDidRun
                )
            }
        }
        .id(controller.screen)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: controller.screen)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
