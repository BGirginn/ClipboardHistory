import SwiftUI

struct ScrollReversalAxisGroupView: View {
    let title: String
    let detail: String
    @Binding var vertical: Bool
    @Binding var horizontal: Bool
    let identifierPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Reverse Vertical Scrolling", isOn: $vertical)
                .accessibilityIdentifier("\(identifierPrefix).vertical")
            Toggle("Reverse Horizontal Scrolling", isOn: $horizontal)
                .accessibilityIdentifier("\(identifierPrefix).horizontal")
        }
    }
}
