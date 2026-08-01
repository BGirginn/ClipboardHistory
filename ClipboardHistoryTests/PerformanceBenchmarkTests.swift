import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class PerformanceBenchmarkTests: XCTestCase {
    func testStorageAndPanelScaleThroughFiveThousandItems() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PerformanceBenchmarkTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let storage = StorageService(baseDirectory: directory, encryptionService: .ephemeral())
        let clock = ContinuousClock()

        let itemCount = 5_000
        let items = (0..<itemCount).map { index in
            ClipboardItem(
                type: .text,
                text: "Benchmark clipboard item \(index)",
                creationDate: Date.now.addingTimeInterval(Double(-itemCount + index)),
                hash: "benchmark-\(index)"
            )
        }
        await storage.saveHistory(items)
        let warmupItems = await storage.loadHistory()
        XCTAssertEqual(warmupItems.count, itemCount)

        let suite = "PerformanceBenchmarkDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = 5_000
        settings.retentionDays = 3_650
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: NSPasteboard(name: .init("BenchmarkPasteboard"))),
            settings: settings,
            startsAutomatically: false
        )
        let warmupLoadStart = clock.now
        await viewModel.loadHistory()
        _ = warmupLoadStart.duration(to: clock.now)
        viewModel.searchText = "clipboard 4999"
        viewModel.searchText = ""
        let warmupView = NSHostingView(rootView: ClipboardPanelView(viewModel: viewModel))
        warmupView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)
        warmupView.layoutSubtreeIfNeeded()

        var writeMilliseconds: [Double] = []
        var readMilliseconds: [Double] = []
        var loadMilliseconds: [Double] = []
        var filterMilliseconds: [Double] = []
        var panelMilliseconds: [Double] = []

        for iteration in 0..<10 {
            let writeStart = clock.now
            await storage.saveHistory(items)
            writeMilliseconds.append(milliseconds(writeStart.duration(to: clock.now)))

            let readStart = clock.now
            let loaded = await storage.loadHistory()
            readMilliseconds.append(milliseconds(readStart.duration(to: clock.now)))
            XCTAssertEqual(loaded.count, itemCount)

            let loadStart = clock.now
            await viewModel.loadHistory()
            loadMilliseconds.append(milliseconds(loadStart.duration(to: clock.now)))

            let filterStart = clock.now
            viewModel.searchText = iteration.isMultiple(of: 2)
                ? "clipboard 4999"
                : "clipboard 2500"
            _ = viewModel.recentItems.count
            filterMilliseconds.append(milliseconds(filterStart.duration(to: clock.now)))
            viewModel.searchText = ""

            let panelStart = clock.now
            let hostingView = NSHostingView(
                rootView: ClipboardPanelView(viewModel: viewModel)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)
            hostingView.layoutSubtreeIfNeeded()
            panelMilliseconds.append(milliseconds(panelStart.duration(to: clock.now)))
            XCTAssertEqual(hostingView.fittingSize.width, 380, accuracy: 1)
        }

        let writeP95 = p95(writeMilliseconds)
        let readP95 = p95(readMilliseconds)
        let loadP95 = p95(loadMilliseconds)
        let filterP95 = p95(filterMilliseconds)
        let panelP95 = p95(panelMilliseconds)
        XCTAssertEqual(viewModel.items.count, itemCount)
        #if DEBUG
        // Coverage and debug instrumentation are intentionally not the release
        // performance gate. Keep this run useful for large-data regressions while
        // the optimized Release run below retains the published p95 limits.
        let instrumentationAllowance = 2.0
        #else
        let instrumentationAllowance = 1.0
        #endif
        XCTAssertLessThanOrEqual(writeP95, 100 * instrumentationAllowance)
        XCTAssertLessThanOrEqual(readP95, 50 * instrumentationAllowance)
        XCTAssertLessThanOrEqual(loadP95, 100 * instrumentationAllowance)
        XCTAssertLessThanOrEqual(filterP95, 50 * instrumentationAllowance)
        XCTAssertLessThanOrEqual(panelP95, 120 * instrumentationAllowance)
        AppLog.performance.notice(
            "benchmark items=5000 repetitions=10 writeP95Ms=\(writeP95) readP95Ms=\(readP95) viewModelLoadP95Ms=\(loadP95) filterP95Ms=\(filterP95) panelP95Ms=\(panelP95)"
        )

        viewModel.prepareForShutdown()
        await storage.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
        let fractional = Double(components.attoseconds) / 1_000_000_000_000_000_000
        return ((seconds + fractional) * 1_000_000).rounded() / 1_000
    }

    private func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let index = max(0, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
        return sorted[index]
    }
}
