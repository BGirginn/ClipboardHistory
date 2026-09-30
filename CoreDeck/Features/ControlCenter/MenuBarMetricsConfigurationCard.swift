import SwiftUI

struct MenuBarMetricsConfigurationCard: View {
    @ObservedObject var model: ControlCenterModel
    @State private var showsAdvanced: Bool

    init(model: ControlCenterModel, showsAdvanced: Bool = false) {
        self.model = model
        _showsAdvanced = State(initialValue: showsAdvanced)
    }

    var body: some View {
        Section {
            Toggle("Show Live Metrics in Menu Bar", isOn: visibleBinding)
                .accessibilityIdentifier("customize.metrics.visible")
            if model.showsSystemMetricsInMenuBar {
                Picker("Density", selection: densityBinding) {
                    ForEach(MenuBarMetricDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    Toggle("Use Separate Menu-Bar Items", isOn: separateBinding)
                        .accessibilityIdentifier("customize.metrics.separate")
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
            }
        } header: {
            Label("Live System Metrics", systemImage: "waveform.path.ecg")
        } footer: {
            Text("The menu bar shows two or three prioritized metrics. Every selected metric remains available in System Monitor.")
        }

        if model.showsSystemMetricsInMenuBar {
            Section("Metrics and Order") {
                ForEach(model.configuration.metricGroup.metrics) { metric in
                    Label(metric.title, systemImage: metric.systemImage)
                        .accessibilityIdentifier("customize.metric.\(metric.rawValue)")
                }
                .onMove(perform: model.moveMetrics)

                Menu("Add Metric", systemImage: "plus") {
                    ForEach(availableMetrics) { metric in
                        Button(metric.title, systemImage: metric.systemImage) {
                            model.setMetricVisible(true, metric: metric)
                        }
                    }
                }
                .disabled(availableMetrics.isEmpty)

                if !model.configuration.metricGroup.metrics.isEmpty {
                    Menu("Remove Metric", systemImage: "minus") {
                        ForEach(model.configuration.metricGroup.metrics) { metric in
                            Button(metric.title, systemImage: metric.systemImage) {
                                model.setMetricVisible(false, metric: metric)
                            }
                        }
                    }
                }
            }
        }
    }

    private var availableMetrics: [MenuBarMetricID] {
        MenuBarMetricID.allCases.filter {
            !model.configuration.metricGroup.metrics.contains($0)
        }
    }

    private var visibleBinding: Binding<Bool> {
        Binding(
            get: { model.showsSystemMetricsInMenuBar },
            set: { model.setMetricGroupVisible($0) }
        )
    }

    private var densityBinding: Binding<MenuBarMetricDensity> {
        Binding(
            get: { model.configuration.metricGroup.density },
            set: { model.setMetricDensity($0) }
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
            set: { value in updateFormats { $0.memory = value } }
        )
    }

    private var temperatureUnitBinding: Binding<TemperatureMetricUnit> {
        Binding(
            get: { model.configuration.metricFormats.temperature },
            set: { value in updateFormats { $0.temperature = value } }
        )
    }

    private var rateUnitBinding: Binding<RateMetricUnit> {
        Binding(
            get: { model.configuration.metricFormats.rate },
            set: { value in updateFormats { $0.rate = value } }
        )
    }

    private func updateFormats(_ mutation: (inout MetricFormatPreferences) -> Void) {
        var formats = model.configuration.metricFormats
        mutation(&formats)
        model.setMetricFormats(formats)
    }
}
