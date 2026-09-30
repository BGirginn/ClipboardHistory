import Foundation

@MainActor
extension MenuBarController {
    func togglePopover() {
        isPopoverShown ? closePopover() : showPopover()
    }

    func showPopover() {
        showPopover(destination: .controlCenter, anchorID: .controlCenter)
    }

    func showControlCenter() {
        showPopover(destination: .controlCenter, anchorID: .controlCenter)
    }

    func showActiveFeature() {
        showPopover(
            destination: appModel.router.activeFeature,
            anchorID: activeAnchorID,
            preparesDestination: false
        )
    }
}
