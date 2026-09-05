import SwiftUI

struct MenuBarPreview: View {
    @ObservedObject var model: ControlCenterModel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Command-drag actual items to reorder them")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                if model.configuration.showsControlCenterItem {
                    previewIcon("square.grid.2x2", label: String(localized: "Control Center"))
                }
                ForEach(previewFeatures) { descriptor in
                    previewIcon(
                        descriptor.systemImage,
                        label: descriptor.title,
                        conditional: model.configuration(for: descriptor.id)
                            .placement.menuBarVisibility == .whenActive
                    )
                }
                if model.configuration.metricGroup.isVisible {
                    metricPreview
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26)
            .padding(.horizontal, 10)
            .background(.bar, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Menu bar preview")
    }

    private var previewFeatures: [FeatureDescriptor] {
        model.registry.descriptors.filter {
            $0.id != .systemMonitor
                && model.configuration(for: $0.id).placement.menuBarVisibility == .always
        }
    }

    private var metricPreview: some View {
        HStack(spacing: 6) {
            ForEach(visibleMetrics) { metric in
                metricPreview(metric)
            }
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func metricPreview(_ metric: MenuBarMetricID) -> some View {
        if let label = metric.menuBarTextLabel {
            VStack(spacing: -1) {
                Text(label).font(.system(size: 8))
                Text(sampleValue(for: metric))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .fixedSize()
        } else {
            HStack(spacing: 2) {
                if let symbol = metric.menuBarSymbol {
                    Image(systemName: symbol)
                }
                Text(sampleValue(for: metric))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    private var visibleMetrics: [MenuBarMetricID] {
        let metrics = model.configuration.visibleMenuBarMetrics
        guard !model.configuration.metricGroup.showsSeparateItems else { return metrics }
        return Array(metrics.prefix(model.configuration.metricGroup.density.visibleMetricLimit))
    }

    private func previewIcon(
        _ symbol: String,
        label: String,
        conditional: Bool = false
    ) -> some View {
        Image(systemName: symbol)
            .frame(width: 16, height: 20)
            .foregroundStyle(conditional ? .secondary : .primary)
            .overlay(alignment: .topTrailing) {
                if conditional, differentiateWithoutColor {
                    Circle().stroke(lineWidth: 1).frame(width: 5, height: 5)
                }
            }
            .accessibilityLabel(label)
            .accessibilityValue(conditional ? String(localized: "When Active") : "")
    }

    private func sampleValue(for metric: MenuBarMetricID) -> String {
        switch metric {
        case .cpu: "24%"
        case .memory: "61%"
        case .temperature: "52°C"
        case .networkDownload: "1.2M"
        case .networkUpload: "320K"
        case .diskRead: "18M"
        case .diskWrite: "4M"
        }
    }
}
