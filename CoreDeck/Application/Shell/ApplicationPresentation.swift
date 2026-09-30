import SwiftUI

struct ApplicationPresentation: EnvironmentKey, Sendable {
    static let defaultValue = ApplicationPresentation()
    var isWindow = false
    var openWindow: (@MainActor @Sendable () -> Void)?
}

extension EnvironmentValues {
    var applicationPresentation: ApplicationPresentation {
        get { self[ApplicationPresentation.self] }
        set { self[ApplicationPresentation.self] = newValue }
    }
}
