import SwiftUI

struct MenuBarMetricsConfigurationCard: View {
    @ObservedObject var model: ControlCenterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live System Metrics", systemImage: "waveform.path.ecg")
                .font(.headline)
            Text("Choose the values shown directly in the menu bar. Values can share one item or use separate movable items.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle("Show Live Metrics in Menu Bar", isOn: visibleBinding)
            if model.configuration.metricGroup.isVisible {
                Toggle("Use Separate Menu-Bar Items", isOn: separateBinding)
                Picker("Display Style", selection: styleBinding) {
                    ForEach(MenuBarMetricStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Memory Format", selection: memoryFormatBinding) {
                    Text("Percentage").tag(MemoryMetricFormat.percentage)
                    Text("Used / Total").tag(MemoryMetricFormat.usedAndTotal)
                }
                Picker("Temperature Unit", selection: temperatureUnitBinding) {
                    Text("Celsius").tag(TemperatureMetricUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureMetricUnit.fahrenheit)
                }
                Picker("Rate Unit", selection: rateUnitBinding) {
                    Text("Automatic").tag(RateMetricUnit.automatic)
                    Text("KB/s").tag(RateMetricUnit.kilobytes)
                    Text("MB/s").tag(RateMetricUnit.megabytes)
                    Text("GB/s").tag(RateMetricUnit.gigabytes)
                }
            }
            Divider()
            ForEach(MenuBarMetricID.allCases) { metric in
                HStack {
                    Toggle(metric.title, isOn: metricBinding(metric))
                    Spacer()
                    if model.configuration.metricGroup.metrics.contains(metric),
                       !model.configuration.metricGroup.showsSeparateItems {
                        Button("Move Up", systemImage: "chevron.up") {
                            model.moveMetric(metric, direction: -1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(model.configuration.metricGroup.metrics.first == metric)
                        Button("Move Down", systemImage: "chevron.down") {
                            model.moveMetric(metric, direction: 1)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(model.configuration.metricGroup.metrics.last == metric)
                    }
                }
            }
        }
        .padding(AppDesign.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: AppDesign.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.cardCornerRadius)
                .stroke(.separator, lineWidth: 1)
        }
    }

    private var visibleBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.metricGroup.isVisible },
            set: { model.setMetricGroupVisible($0) }
        )
    }

    private var separateBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.metricGroup.showsSeparateItems },
            set: { model.setMetricsAsSeparateItems($0) }
        )
    }

    private var styleBinding: Binding<MenuBarMetricStyle> {
        Binding(
            get: { model.configuration.metricGroup.style },
            set: { model.setMetricStyle($0) }
        )
    }

    private var memoryFormatBinding: Binding<MemoryMetricFormat> {
        Binding(
            get: { model.configuration.metricFormats.memory },
            set: { value in
                var formats = model.configuration.metricFormats
                formats.memory = value
                model.setMetricFormats(formats)
            }
        )
    }

    private var temperatureUnitBinding: Binding<TemperatureMetricUnit> {
        Binding(
            get: { model.configuration.metricFormats.temperature },
            set: { value in
                var formats = model.configuration.metricFormats
                formats.temperature = value
                model.setMetricFormats(formats)
            }
        )
    }

    private var rateUnitBinding: Binding<RateMetricUnit> {
        Binding(
            get: { model.configuration.metricFormats.rate },
            set: { value in
                var formats = model.configuration.metricFormats
                formats.rate = value
                model.setMetricFormats(formats)
            }
        )
    }

    private func metricBinding(_ metric: MenuBarMetricID) -> Binding<Bool> {
        Binding(
            get: { model.configuration.metricGroup.metrics.contains(metric) },
            set: { model.setMetricVisible($0, metric: metric) }
        )
    }
}
