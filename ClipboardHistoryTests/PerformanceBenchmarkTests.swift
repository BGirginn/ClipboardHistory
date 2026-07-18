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

        for count in [100, 500, 1_000, 5_000] {
            let items = (0..<count).map { index in
                ClipboardItem(
                    type: .text,
                    text: "Benchmark clipboard item \(index)",
                    creationDate: Date.now.addingTimeInterval(Double(-count + index)),
                    hash: "benchmark-\(index)"
                )
            }
            let writeStart = clock.now
            await storage.saveHistory(items)
            let writeDuration = writeStart.duration(to: clock.now)
            let readStart = clock.now
            let loaded = await storage.loadHistory()
            let readDuration = readStart.duration(to: clock.now)

            XCTAssertEqual(loaded.count, count)
            AppLog.performance.notice(
                "benchmark items=\(count) writeMs=\(self.milliseconds(writeDuration)) readMs=\(self.milliseconds(readDuration))"
            )
        }

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
        let loadStart = clock.now
        await viewModel.loadHistory()
        let viewModelLoadDuration = loadStart.duration(to: clock.now)
        let filterStart = clock.now
        viewModel.searchText = "clipboard 4999"
        let filterDuration = filterStart.duration(to: clock.now)
        let panelStart = clock.now
        let hostingView = NSHostingView(rootView: ClipboardPanelView(viewModel: viewModel))
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)
        hostingView.layoutSubtreeIfNeeded()
        let panelDuration = panelStart.duration(to: clock.now)

        XCTAssertEqual(viewModel.items.count, 5_000)
        XCTAssertEqual(viewModel.recentItems.count, 1)
        XCTAssertEqual(hostingView.fittingSize.width, 380, accuracy: 1)
        AppLog.performance.notice(
            "benchmark items=5000 viewModelLoadMs=\(self.milliseconds(viewModelLoadDuration)) filterMs=\(self.milliseconds(filterDuration)) panelRenderMs=\(self.milliseconds(panelDuration))"
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
}
