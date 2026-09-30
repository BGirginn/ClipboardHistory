import SwiftUI

struct ScrollReversalCardView: View {
    @ObservedObject var controller: ScrollReversalController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Scroll Reverse", isOn: $controller.isEnabled)
                    .accessibilityIdentifier("scrollReversal.enabled")

                Text(
                    "Line-based mouse-wheel events and precise trackpad or Magic Mouse events can be configured separately."
                )
                .foregroundStyle(.secondary)

                if controller.isEnabled {
                    Divider()
                    ScrollReversalAxisGroupView(
                        title: String(localized: "Mouse Wheel"),
                        detail: String(localized: "Line-based scrolling"),
                        vertical: $controller.reversesDiscreteVertical,
                        horizontal: $controller.reversesDiscreteHorizontal,
                        identifierPrefix: "scrollReversal.discrete"
                    )

                    Divider()
                    ScrollReversalAxisGroupView(
                        title: String(localized: "Trackpad and Precise Devices"),
                        detail: String(localized: "Pixel-based scrolling, including Magic Mouse"),
                        vertical: $controller.reversesPreciseVertical,
                        horizontal: $controller.reversesPreciseHorizontal,
                        identifierPrefix: "scrollReversal.precise"
                    )

                    ScrollReversalStatusView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                "Scroll Reverse",
                systemImage: controller.isActive
                    ? "arrow.up.arrow.down.circle.fill"
                    : "arrow.up.arrow.down.circle"
            )
        }
        .accessibilityIdentifier("scrollReversal.card")
    }

}
