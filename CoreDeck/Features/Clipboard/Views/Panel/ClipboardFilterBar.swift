import SwiftUI

struct ClipboardFilterBar: View {
    let settings: AppSettings

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ClipboardSegmentedFilterControls(settings: settings)
            ClipboardCompactFilterControls(settings: settings)
        }
        .padding(.horizontal, ClipboardPanelLayout.horizontalPadding)
        .padding(.vertical, 7)
    }
}
