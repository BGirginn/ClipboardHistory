import Foundation

struct ManagedFilename: Equatable, Sendable {
    let value: String

    init?(_ value: String) {
        guard !value.isEmpty,
              value.utf8.count <= 255,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains(":"),
              !value.contains("\0"),
              URL(fileURLWithPath: value).lastPathComponent == value else {
            return nil
        }
        self.value = value
    }
}
