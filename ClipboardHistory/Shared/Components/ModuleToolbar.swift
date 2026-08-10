import SwiftUI

struct ModuleToolbar<Actions: View>: View {
    let title: String
    let subtitle: String?
    let backTitle: String
    let back: () -> Void
    let openSettings: (() -> Void)?
    @ViewBuilder let actions: Actions

    init(
        title: String,
        subtitle: String?,
        backTitle: String,
        back: @escaping () -> Void,
        openSettings: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backTitle = backTitle
        self.back = back
        self.openSettings = openSettings
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(backTitle, systemImage: "chevron.left", action: back)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
                .help(backTitle)
                .accessibilityIdentifier("module.back")

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)
            if let openSettings {
                Button("Open Settings", systemImage: "gearshape", action: openSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .frame(width: AppDesign.controlSize, height: AppDesign.controlSize)
                    .help("Open Settings")
                    .accessibilityIdentifier("module.settings")
            }
            actions
        }
        .padding(.horizontal, AppDesign.horizontalPadding)
        .padding(.vertical, AppDesign.toolbarVerticalPadding)
    }
}
