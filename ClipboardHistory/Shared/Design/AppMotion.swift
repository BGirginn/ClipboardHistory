import SwiftUI

enum AppMotion {
    static func transition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.14)
    }
}
