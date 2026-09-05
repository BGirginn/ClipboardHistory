import SwiftUI

struct CompactSystemMetricCard<ChartContent: View>: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let progress: Double?
    let details: [(label: String, value: String)]
    let chartContent: ChartContent

    init(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        progress: Double? = nil,
        details: [(label: String, value: String)] = [],
        @ViewBuilder chartContent: () -> ChartContent
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.progress = progress
        self.details = details
        self.chartContent = chartContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let progress {
                ProgressView(value: min(max(progress, 0), 100), total: 100)
                    .tint(tint)
                    .accessibilityLabel(title)
                    .accessibilityValue(value)
            }
            chartContent
            ForEach(details.indices, id: \.self) { index in
                LabeledContent(details[index].label) {
                    Text(details[index].value)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .font(.footnote)
            }
        }
        .padding(AppDesign.compactCardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cardCornerRadius)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
