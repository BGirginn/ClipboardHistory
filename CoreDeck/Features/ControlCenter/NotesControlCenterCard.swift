import SwiftUI

struct NotesControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: NoteController
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: controller.notes.count == 1
                ? String(localized: "1 saved note")
                : String(localized: "\(controller.notes.count) saved notes"),
            systemImage: descriptor.systemImage,
            accessorySystemImage: "chevron.right",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }
}
