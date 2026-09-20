import SwiftUI

struct DrawerView: View {
    @ObservedObject var model: ControlCenterModel
    let openFeature: (UtilityFeatureID) -> Void
    let restoreFeature: (UtilityFeatureID) -> Void
    let customize: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Drawer")
                    .font(.headline)
                Spacer()
                Button("Customize Menu Bar", systemImage: "slider.horizontal.3", action: customize)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Customize Menu Bar")
                    .accessibilityIdentifier("drawer.customize")
            }

            if model.drawerFeatures.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drawer is Empty")
                            .font(.subheadline.weight(.semibold))
                        Text("Move a CoreDeck menu-bar item here from Customize Menu Bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.drawerFeatures) { descriptor in
                            drawerItem(descriptor)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .frame(minWidth: 320, idealWidth: 380, minHeight: 96)
        .accessibilityIdentifier("drawer.content")
    }

    private func drawerItem(_ descriptor: FeatureDescriptor) -> some View {
        VStack(spacing: 4) {
            Button {
                openFeature(descriptor.id)
            } label: {
                Image(systemName: descriptor.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(descriptor.title)
            .accessibilityLabel(descriptor.title)
            .accessibilityIdentifier("drawer.feature.\(descriptor.id.rawValue)")

            HStack(spacing: 2) {
                Text(descriptor.title)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Restore to Menu Bar", systemImage: "arrow.up.to.line") {
                    restoreFeature(descriptor.id)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Restore to Menu Bar")
                .accessibilityIdentifier("drawer.restore.\(descriptor.id.rawValue)")
            }
        }
        .frame(width: 104)
    }
}
