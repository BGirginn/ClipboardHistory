import SwiftUI

struct AudioMixerControlCenterCard: View {
    let descriptor: FeatureDescriptor
    @ObservedObject var controller: AudioMixerController
    let action: () -> Void

    var body: some View {
        ControlCenterFeatureCard(
            title: descriptor.title,
            summary: summary,
            systemImage: controller.isEverythingMuted
                ? "speaker.slash.fill"
                : descriptor.systemImage,
            accessorySystemImage: "chevron.right",
            accessibilityIdentifier: "controlCenter.\(descriptor.id.rawValue)",
            action: action
        )
    }

    private var summary: String {
        let applicationCount = controller.outputApplications.count
        let tabCount = controller.browserTabs.count
        return String(localized: "\(applicationCount) audio apps · \(tabCount) controlled tabs")
    }
}
