import QuickLookUI

@MainActor
protocol QuickLookPanelControlling: AnyObject {
    func present(
        dataSource: any QLPreviewPanelDataSource,
        delegate: any QLPreviewPanelDelegate
    )
    func orderOut()
}
