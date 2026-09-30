import Foundation

actor FileDrawerStateStore: DrawerStateStoring {
    enum StoreError: LocalizedError {
        case invalidFile
        case unsupportedConfiguration(Int)
        case unsupportedJournal(Int)

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                "Drawer state is not a bounded regular file."
            case let .unsupportedConfiguration(version):
                "Unsupported drawer configuration version: \(version)."
            case let .unsupportedJournal(version):
                "Unsupported drawer journal version: \(version)."
            }
        }
    }

    private let directory: URL
    private let configurationURL: URL
    private let journalURL: URL
    private let maximumFileSize = 1_048_576

    init(directory: URL) {
        self.directory = directory.standardizedFileURL
        configurationURL = directory.appending(path: "configuration.json").standardizedFileURL
        journalURL = directory.appending(path: "operation-journal.json").standardizedFileURL
    }

    func loadConfiguration() throws -> DrawerConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return .defaults
        }
        let configuration = try decode(DrawerConfiguration.self, from: configurationURL)
        guard configuration.version == DrawerConfiguration.currentVersion else {
            throw StoreError.unsupportedConfiguration(configuration.version)
        }
        return configuration
    }

    func saveConfiguration(_ configuration: DrawerConfiguration) throws {
        guard configuration.version == DrawerConfiguration.currentVersion else {
            throw StoreError.unsupportedConfiguration(configuration.version)
        }
        try write(configuration, to: configurationURL)
    }

    func loadJournal() throws -> DrawerOperationJournal? {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
        let journal = try decode(DrawerOperationJournal.self, from: journalURL)
        guard journal.version == DrawerOperationJournal.currentVersion else {
            throw StoreError.unsupportedJournal(journal.version)
        }
        return journal
    }

    func saveJournal(_ journal: DrawerOperationJournal) throws {
        guard journal.version == DrawerOperationJournal.currentVersion else {
            throw StoreError.unsupportedJournal(journal.version)
        }
        try write(journal, to: journalURL)
    }

    func removeJournal() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        try FileManager.default.removeItem(at: journalURL)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumFileSize else {
            throw StoreError.invalidFile
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumFileSize else { throw StoreError.invalidFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
