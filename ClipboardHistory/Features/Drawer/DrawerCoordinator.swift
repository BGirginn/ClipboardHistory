import Combine
import Foundation

@MainActor
final class DrawerCoordinator: ObservableObject {
    @Published private(set) var configuration: DrawerConfiguration = .defaults
    @Published private(set) var discoveredItems: [DrawerItemObservation] = []
    @Published private(set) var recoveryState: DrawerRecoveryState = .recovered
    @Published private(set) var errorMessage: String?
    @Published private(set) var isOperating = false

    private let discovery: any ExternalMenuBarItemDiscovering
    private let mover: any ExternalMenuBarItemMoving
    private let activator: any ExternalMenuBarItemActivating
    private let observer: any ExternalMenuBarItemObserving
    private let conflictDetector: any MenuBarConflictDetecting
    private let stateStore: any DrawerStateStoring

    init(
        discovery: any ExternalMenuBarItemDiscovering,
        mover: any ExternalMenuBarItemMoving,
        activator: any ExternalMenuBarItemActivating,
        observer: any ExternalMenuBarItemObserving,
        conflictDetector: any MenuBarConflictDetecting,
        stateStore: any DrawerStateStoring
    ) {
        self.discovery = discovery
        self.mover = mover
        self.activator = activator
        self.observer = observer
        self.conflictDetector = conflictDetector
        self.stateStore = stateStore
    }

    func load() async {
        do {
            configuration = try await stateStore.loadConfiguration()
            if try await stateStore.loadJournal() != nil {
                recoveryState = .interventionRequired
                errorMessage = String(localized: "Drawer recovery is required before external items can be managed.")
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            recoveryState = .interventionRequired
        }
    }

    func refresh() async {
        do {
            let observations = try await discovery.discoverItems()
            let hasConflict = await conflictDetector.hasConflict(in: observations)
            guard !hasConflict else {
                errorMessage = String(localized: "Another menu-bar change was detected. External management is paused.")
                return
            }
            discoveredItems = observations.sorted { $0.id.persistenceKey < $1.id.persistenceKey }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setExternalManagementEnabled(_ enabled: Bool) async -> Bool {
        guard !isOperating else { return false }
        if !enabled {
            for item in configuration.items where item.desiredPlacement == .drawer {
                guard case .succeeded = await restoreToMenuBar(item.id) else { return false }
            }
        }
        var updated = configuration
        updated.externalManagementEnabled = enabled
        do {
            try await stateStore.saveConfiguration(updated)
            configuration = updated
            if !enabled { discoveredItems = [] }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func moveToDrawer(_ id: ManagedMenuBarItemID) async -> DrawerOperationResult {
        await changePlacement(of: id, to: .drawer)
    }

    func restoreToMenuBar(_ id: ManagedMenuBarItemID) async -> DrawerOperationResult {
        await changePlacement(of: id, to: .menuBar)
    }

    func activate(_ request: DrawerActivationRequest) async -> DrawerOperationResult {
        guard configuration.externalManagementEnabled else {
            return failure("External drawer management is disabled.", recovery: .recovered)
        }
        do {
            guard let item = try await observer.observation(for: request.itemID),
                  item.capabilities.contains(.activate) else {
                return failure("The menu-bar item cannot be activated safely.", recovery: .recovered)
            }
            try await activator.activate(request)
            return .succeeded(item)
        } catch {
            return failure(error.localizedDescription, recovery: recoveryState)
        }
    }

    func retryRecovery() async -> DrawerOperationResult {
        guard !isOperating else {
            return failure("Another drawer operation is running.", recovery: recoveryState)
        }
        do {
            guard let journal = try await stateStore.loadJournal() else {
                recoveryState = .recovered
                errorMessage = nil
                return failure("There is no drawer operation to recover.", recovery: .recovered)
            }
            return await restore(journal: journal, operationFailure: journal.failure)
        } catch {
            return failure(error.localizedDescription, recovery: .interventionRequired)
        }
    }

    private func changePlacement(
        of id: ManagedMenuBarItemID,
        to placement: DrawerPlacement
    ) async -> DrawerOperationResult {
        guard configuration.externalManagementEnabled else {
            return failure("External drawer management is disabled.", recovery: .recovered)
        }
        guard recoveryState != .interventionRequired, !isOperating else {
            return failure("Resolve the pending drawer recovery first.", recovery: recoveryState)
        }
        isOperating = true
        defer { isOperating = false }
        do {
            let observations = try await discovery.discoverItems()
            let hasConflict = await conflictDetector.hasConflict(in: observations)
            guard !hasConflict else {
                return failure(
                    "Another menu-bar change was detected. No item was moved.",
                    recovery: .recovered
                )
            }
            guard let original = observations.first(where: { $0.id == id }) else {
                return failure("The requested menu-bar item was not found.", recovery: .recovered)
            }
            let required: DrawerItemCapabilities = placement == .drawer
                ? [.move, .reclaimSpace, .observe, .restore]
                : [.move, .observe, .restore]
            guard original.capabilities.isSuperset(of: required) else {
                return failure("The requested placement is not supported safely.", recovery: .recovered)
            }
            var journal = DrawerOperationJournal(
                version: DrawerOperationJournal.currentVersion,
                operationID: UUID(),
                createdAt: .now,
                requestedPlacement: placement,
                original: original,
                observed: nil,
                phase: .prepared,
                failure: nil
            )
            try await stateStore.saveJournal(journal)
            try await mover.move(original, to: placement)
            guard let observed = try await observer.observation(for: id),
                  observed.placement == placement else {
                throw OperationError.verificationFailed
            }
            journal.observed = observed
            journal.phase = .moved
            try await stateStore.saveJournal(journal)

            var updated = configuration
            updated.setPlacement(placement, for: id)
            try await stateStore.saveConfiguration(updated)
            configuration = updated
            try await stateStore.removeJournal()
            recoveryState = .recovered
            errorMessage = nil
            await refresh()
            return .succeeded(observed)
        } catch {
            guard let journal = try? await stateStore.loadJournal() else {
                return failure(error.localizedDescription, recovery: .interventionRequired)
            }
            return await restore(journal: journal, operationFailure: error.localizedDescription)
        }
    }

    private func restore(
        journal: DrawerOperationJournal,
        operationFailure: String?
    ) async -> DrawerOperationResult {
        recoveryState = .restoring
        var updatedJournal = journal
        updatedJournal.phase = .restoring
        updatedJournal.failure = operationFailure
        do {
            try await stateStore.saveJournal(updatedJournal)
            try await mover.restore(journal.original)
            guard let restored = try await observer.observation(for: journal.original.id),
                  restored.placement == journal.original.placement,
                  restored.matchesTopology(of: journal.original) else {
                throw OperationError.restoreVerificationFailed
            }
            try await stateStore.removeJournal()
            recoveryState = .recovered
            errorMessage = operationFailure
            await refresh()
            return .failed(
                message: operationFailure ?? String(localized: "The drawer operation was restored."),
                recovery: .recovered
            )
        } catch {
            updatedJournal.phase = .restoreFailed
            updatedJournal.failure = [operationFailure, error.localizedDescription]
                .compactMap { $0 }.joined(separator: " | ")
            try? await stateStore.saveJournal(updatedJournal)
            return failure(updatedJournal.failure ?? error.localizedDescription, recovery: .interventionRequired)
        }
    }

    private func failure(
        _ message: String,
        recovery: DrawerRecoveryState
    ) -> DrawerOperationResult {
        recoveryState = recovery
        errorMessage = message
        return .failed(message: message, recovery: recovery)
    }

    private enum OperationError: LocalizedError {
        case verificationFailed
        case restoreVerificationFailed

        var errorDescription: String? {
            switch self {
            case .verificationFailed:
                "The requested drawer placement could not be verified."
            case .restoreVerificationFailed:
                "The original menu-bar placement could not be restored."
            }
        }
    }
}
