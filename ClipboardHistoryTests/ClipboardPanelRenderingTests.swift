import AppKit
import SwiftUI
import XCTest
@testable import ClipboardHistory

@MainActor
final class ClipboardPanelRenderingTests: XCTestCase {
    func testEmptyPanelRendersAtRequestedSize() async {
        let context = makeContext()
        let hostingView = NSHostingView(
            rootView: ClipboardPanelView(viewModel: context.viewModel)
        )

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(hostingView.fittingSize.width, 380, accuracy: 0.5)
        XCTAssertEqual(hostingView.fittingSize.height, 500, accuracy: 0.5)
        await cleanup(context)
    }

    func testPanelAndProblematicSettingsStatesRender() async throws {
        let context = makeContext()
        do {
            context.viewModel.setPrivateModeEnabled(true)
            context.viewModel.lockService.configure(
                enabled: true,
                option: .never
            )
            context.viewModel.lock()
            try render(
                ClipboardPanelView(viewModel: context.viewModel),
                named: "panel-private-locked-light",
                colorScheme: .light
            )

            for (index, section) in ClipboardSettingsSection.allCases.enumerated() {
                let colorScheme: ColorScheme = index.isMultiple(of: 2) ? .light : .dark
                try render(
                    ClipboardSettingsView(
                        viewModel: context.viewModel,
                        initialSection: section
                    )
                    .frame(width: 380, height: 500),
                    named: "settings-\(section.rawValue)-\(colorScheme == .dark ? "dark" : "light")",
                    colorScheme: colorScheme
                )
            }
        } catch {
            await cleanup(context)
            throw error
        }
        await cleanup(context)
    }

    private func render<Content: View>(
        _ content: Content,
        named name: String,
        colorScheme: ColorScheme
    ) throws {
        let hostingView = NSHostingView(
            rootView: content.environment(\.colorScheme, colorScheme)
        )
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 500)
        hostingView.wantsLayer = true
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        XCTAssertEqual(representation.pixelsWide, 760, accuracy: 2)
        XCTAssertEqual(representation.pixelsHigh, 1_000, accuracy: 2)

        let outputDirectory = ProcessInfo.processInfo.environment[
            "CLIPBOARD_HISTORY_RENDER_OUTPUT"
        ] ?? "/tmp/ClipboardHistoryUI"
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let png = try XCTUnwrap(
            representation.representation(using: .png, properties: [:])
        )
        try png.write(
            to: directory.appending(path: "\(name).png"),
            options: .atomic
        )
    }

    private struct Context {
        let directory: URL
        let defaultsSuite: String
        let storage: StorageService
        let viewModel: ClipboardHistoryViewModel
    }

    private func makeContext() -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ClipboardPanelRenderingTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let pasteboard = NSPasteboard(
            name: .init("PanelRenderingTests-\(UUID().uuidString)")
        )
        let defaultsSuite = "PanelRenderingDefaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let storage = StorageService(baseDirectory: directory)
        let viewModel = ClipboardHistoryViewModel(
            storage: storage,
            monitor: ClipboardMonitor(pasteboard: pasteboard),
            restorePasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            startsAutomatically: false
        )
        return Context(
            directory: directory,
            defaultsSuite: defaultsSuite,
            storage: storage,
            viewModel: viewModel
        )
    }

    private func cleanup(_ context: Context) async {
        context.viewModel.prepareForShutdown()
        await context.storage.close()
        UserDefaults.standard.removePersistentDomain(forName: context.defaultsSuite)
        try? FileManager.default.removeItem(at: context.directory)
    }
}
