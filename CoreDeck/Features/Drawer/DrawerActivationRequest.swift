import AppKit

struct DrawerActivationRequest: Sendable {
    let itemID: ManagedMenuBarItemID
    let mouseButton: Int
    let modifierRawValue: UInt

    init(itemID: ManagedMenuBarItemID, event: NSEvent?) {
        self.itemID = itemID
        mouseButton = event?.buttonNumber ?? 0
        modifierRawValue = event?.modifierFlags
            .intersection(.deviceIndependentFlagsMask).rawValue ?? 0
    }
}
