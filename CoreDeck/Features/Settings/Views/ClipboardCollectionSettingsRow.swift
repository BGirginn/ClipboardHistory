import SwiftUI

struct ClipboardCollectionSettingsRow: View {
    @ObservedObject var viewModel: SettingsFeatureModel
    let collection: ClipboardCollection

    var body: some View {
        HStack {
            Label(collection.name, systemImage: "folder")
            Spacer()
            Button(
                "Delete \(collection.name)",
                systemImage: "trash",
                role: .destructive,
                action: deleteCollection
            )
            .labelStyle(.iconOnly)
        }
    }

    func deleteCollection() {
        viewModel.deleteCollection(collection)
    }
}
