import SwiftUI

struct AudioMixerBrowserSection: View {
    @ObservedObject var controller: AudioMixerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Browser Tabs").font(.headline)
                Spacer()
                Button("Set Up Chromium Extension", systemImage: "puzzlepiece.extension", action: controller.installChromiumExtension)
                    .labelStyle(.iconOnly)
                    .help("Set Up Chromium Extension")
                Button("Open Safari Extension Settings", systemImage: "safari", action: controller.openSafariExtensionSettings)
                    .labelStyle(.iconOnly)
                    .help("Open Safari Extension Settings")
            }
            if controller.browserTabs.isEmpty {
                ContentUnavailableView(
                    "No Controlled Tabs",
                    systemImage: "rectangle.stack.badge.play",
                    description: Text("Install the companion extension, then add a playing tab to the mixer.")
                )
            } else {
                ForEach(controller.browserTabs) { tab in
                    BrowserAudioTabRow(
                        tab: tab,
                        effectiveVolume: controller.effectiveVolume(for: tab),
                        setVolume: { controller.setBrowserVolume($0, tab: tab) },
                        toggleMute: { controller.toggleMute(tab) },
                        activate: { controller.activate(tab) }
                    )
                    if tab.id != controller.browserTabs.last?.id { Divider() }
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }
}
