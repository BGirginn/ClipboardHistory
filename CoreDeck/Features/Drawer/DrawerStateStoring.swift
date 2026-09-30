import Foundation

protocol DrawerStateStoring: Sendable {
    func loadConfiguration() async throws -> DrawerConfiguration
    func saveConfiguration(_ configuration: DrawerConfiguration) async throws
    func loadJournal() async throws -> DrawerOperationJournal?
    func saveJournal(_ journal: DrawerOperationJournal) async throws
    func removeJournal() async throws
}
