import AppKit

@MainActor
extension MenuBarController {
    func positionDetachablePanel(screenEdge: PanelScreenEdge? = nil) {
        guard let detachablePanel,
              detachablePanel.isVisible
                || appModel.settings.panelPresentationMode == .detachable,
              let screen = statusItems[activeAnchorID]?.button?.window?.screen
                ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let panelSize = detachablePanel.frame.size
        let margin = 12.0
        let origin: NSPoint
        switch screenEdge ?? appModel.settings.panelScreenEdge {
        case .left:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.midY - panelSize.height / 2
            )
        case .right:
            origin = NSPoint(
                x: visibleFrame.maxX - panelSize.width - margin,
                y: visibleFrame.midY - panelSize.height / 2
            )
        case .top:
            origin = NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.maxY - panelSize.height - margin
            )
        case .bottom:
            origin = NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.minY + margin
            )
        }
        detachablePanel.setFrameOrigin(origin)
    }
}
