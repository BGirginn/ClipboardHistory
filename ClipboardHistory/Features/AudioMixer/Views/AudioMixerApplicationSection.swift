import SwiftUI

struct AudioMixerApplicationSection: View {
    let applications: [AudioApplication]
    let controller: AudioMixerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applications").font(.headline)
            if applications.isEmpty {
                ContentUnavailableView(
                    "No Audio Applications",
                    systemImage: "speaker.slash",
                    description: Text("Start audio in an application to show it here.")
                )
            } else {
                ForEach(applications, id: \.bundleID) { application in
                    AudioApplicationRow(
                        application: application,
                        previewVolume: { controller.previewVolume($0, for: application) },
                        commitVolume: { controller.setVolume($0, for: application) },
                        toggleMute: { controller.toggleMute(application) }
                    )
                    if application.bundleID != applications.last?.bundleID { Divider() }
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }
}
