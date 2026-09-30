import SwiftUI

struct SystemMetricsOverviewGrid: View {
    let controller: SystemMetricsController

    var body: some View {
        ViewThatFits(in: .horizontal) {
            twoColumnGrid
                .frame(minWidth: 336)
            singleColumnGrid
        }
        .frame(maxWidth: .infinity)
    }

    private var twoColumnGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                SystemCPUCompactCard(controller: controller)
                SystemMemoryCompactCard(controller: controller)
            }
            GridRow {
                SystemTemperatureCompactCard(controller: controller)
                SystemNetworkCompactCard(controller: controller)
            }
            GridRow {
                SystemDiskCompactCard(controller: controller)
                    .gridCellColumns(2)
            }
        }
    }

    private var singleColumnGrid: some View {
        VStack(spacing: 8) {
            SystemCPUCompactCard(controller: controller)
            SystemMemoryCompactCard(controller: controller)
            SystemTemperatureCompactCard(controller: controller)
            SystemNetworkCompactCard(controller: controller)
            SystemDiskCompactCard(controller: controller)
        }
    }
}
