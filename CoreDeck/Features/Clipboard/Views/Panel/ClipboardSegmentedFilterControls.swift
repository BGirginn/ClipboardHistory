import SwiftUI

struct ClipboardSegmentedFilterControls: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            Picker("Filter", selection: $settings.selectedFilter) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("filter.picker")

            ClipboardSortMenu(settings: settings)
        }
    }
}
