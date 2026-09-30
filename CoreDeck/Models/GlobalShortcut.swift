import Carbon
import Foundation

struct GlobalShortcut: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let presets: [GlobalShortcut] = [
        GlobalShortcut(
            id: "command-shift-v",
            title: "Command-Shift-V",
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        GlobalShortcut(
            id: "command-option-v",
            title: "Command-Option-V",
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | optionKey)
        ),
        GlobalShortcut(
            id: "control-option-v",
            title: "Control-Option-V",
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey)
        )
    ]

    static let defaultShortcut = presets[0]
}
