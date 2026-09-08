#if CLIPBOARD_HISTORY_TEST_HOST
import Foundation

final class UITestFileManager: FileManager, @unchecked Sendable {
    private let root: URL

    init(root: URL) {
        self.root = root
        super.init()
    }

    override var temporaryDirectory: URL { root }
}
#endif
