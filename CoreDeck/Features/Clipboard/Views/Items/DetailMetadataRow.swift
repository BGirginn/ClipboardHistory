import SwiftUI

struct DetailMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(5)
                .truncationMode(.middle)
        }
    }
}
