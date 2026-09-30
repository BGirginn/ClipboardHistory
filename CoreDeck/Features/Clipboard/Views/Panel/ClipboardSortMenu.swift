import SwiftUI

struct ClipboardSortMenu: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Sort Order", selection: $settings.selectedSortMode) {
                ForEach(ClipboardSortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
        .labelStyle(.iconOnly)
        .menuStyle(.borderlessButton)
        .frame(
            width: ClipboardPanelLayout.compactControlSize,
            height: ClipboardPanelLayout.compactControlSize
        )
        .help("Sort")
        .accessibilityLabel("Sort")
        .accessibilityValue(settings.selectedSortMode.title)
        .accessibilityIdentifier("sort.menu")
    }
}
