import QuickLookUI

@MainActor
final class SystemQuickLookPanelController: QuickLookPanelControlling {
    private let panel: QLPreviewPanel

    init(panel: QLPreviewPanel) {
        self.panel = panel
    }

    func present(
        dataSource: any QLPreviewPanelDataSource,
        delegate: any QLPreviewPanelDelegate
    ) {
        panel.dataSource = dataSource
        panel.delegate = delegate
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func orderOut() {
        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
    }
}
