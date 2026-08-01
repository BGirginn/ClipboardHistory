import Combine
import Foundation

@MainActor
final class LaunchAtLoginService: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?
    private let backend: any LaunchAtLoginBackend

    init(backend: any LaunchAtLoginBackend = ServiceManagementLaunchAtLoginBackend()) {
        self.backend = backend
        refresh()
    }

    func refresh() {
        isEnabled = backend.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            try backend.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            AppLog.lifecycle.error(
                "Launch-at-login change failed; category=\(String(describing: type(of: error)), privacy: .public)"
            )
        }
        refresh()
    }
}
