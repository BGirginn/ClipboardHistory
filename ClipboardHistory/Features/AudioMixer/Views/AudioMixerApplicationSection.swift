import SwiftUI

struct AudioMixerApplicationSection: View {
    let applications: [AudioApplication]
    @ObservedObject var controller: AudioMixerController

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
                ForEach(applications) { application in
                    AudioApplicationRow(
                        application: application,
                        setVolume: { controller.setVolume($0, for: application) },
                        toggleMute: { controller.toggleMute(application) }
                    )
                    if application.id != applications.last?.id { Divider() }
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
    }
}
