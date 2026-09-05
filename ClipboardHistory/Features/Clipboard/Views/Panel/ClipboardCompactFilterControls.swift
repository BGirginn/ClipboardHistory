import SwiftUI

struct ClipboardCompactFilterControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            Menu(settings.selectedFilter.title, systemImage: "line.3.horizontal.decrease") {
                Picker("Filter", selection: $settings.selectedFilter) {
                    ForEach(ClipboardFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter")
            .accessibilityValue(settings.selectedFilter.title)
            .accessibilityIdentifier("filter.menu")

            Spacer(minLength: 0)

            ClipboardSortMenu(settings: settings)
        }
    }
}
