import AppKit
import XCTest
@testable import ClipboardHistoryTestHost

@MainActor
final class DrawerCoordinatorTests: XCTestCase {
    func testMovePersistsPreferenceOnlyAfterObservedPlacement() async throws {
        let original = observation(placement: .menuBar)
        let services = Services(original: original)
        let coordinator = services.makeCoordinator()

        await coordinator.load()
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)
        let result = await coordinator.moveToDrawer(original.id)

        guard case let .succeeded(observed) = result else {
            return XCTFail("Expected verified movement")
        }
        XCTAssertEqual(observed.placement, .drawer)
        XCTAssertEqual(coordinator.configuration.items.first?.desiredPlacement, .drawer)
        let storedJournal = await services.store.loadJournal()
        let savedJournalPhases = await services.store.savedJournalPhases
        XCTAssertNil(storedJournal)
        XCTAssertEqual(savedJournalPhases, [.prepared, .moved])
        XCTAssertEqual(services.mover.moveCount, 1)
        XCTAssertEqual(services.mover.restoreCount, 0)
    }

    func testFailedMovementRestoresBeforePreferenceCommit() async throws {
        let original = observation(placement: .menuBar)
        let services = Services(original: original)
        services.observer.forcedPlacementAfterMove = .menuBar
        let coordinator = services.makeCoordinator()

        await coordinator.load()
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)
        let result = await coordinator.moveToDrawer(original.id)

        guard case let .failed(message, recovery) = result else {
            return XCTFail("Expected movement failure")
        }
        XCTAssertTrue(message.contains("verified"))
        XCTAssertEqual(recovery, .recovered)
        XCTAssertTrue(coordinator.configuration.items.isEmpty)
        XCTAssertEqual(services.mover.restoreCount, 1)
        let storedJournal = await services.store.loadJournal()
        XCTAssertNil(storedJournal)
    }

    func testRestoreFailureStopsAutomaticWorkAndKeepsJournal() async throws {
        let original = observation(placement: .menuBar)
        let services = Services(original: original)
        services.observer.forcedPlacementAfterMove = .menuBar
        services.mover.restoreError = FixtureError.restoreFailed
        let coordinator = services.makeCoordinator()

        await coordinator.load()
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)
        let result = await coordinator.moveToDrawer(original.id)

        guard case let .failed(_, recovery) = result else {
            return XCTFail("Expected recovery failure")
        }
        XCTAssertEqual(recovery, .interventionRequired)
        let storedJournal = await services.store.loadJournal()
        XCTAssertEqual(storedJournal?.phase, .restoreFailed)
        let second = await coordinator.moveToDrawer(original.id)
        XCTAssertEqual(
            second,
            .failed(
                message: "Resolve the pending drawer recovery first.",
                recovery: .interventionRequired
            )
        )
        XCTAssertEqual(services.mover.moveCount, 1)
    }

    func testPendingJournalRequiresExplicitRecovery() async throws {
        let original = observation(placement: .menuBar)
        let services = Services(original: original)
        await services.store.saveJournal(journal(original: original))
        let coordinator = services.makeCoordinator()

        await coordinator.load()

        XCTAssertEqual(coordinator.recoveryState, .interventionRequired)
        XCTAssertEqual(services.mover.restoreCount, 0)
        let result = await coordinator.retryRecovery()
        guard case let .failed(_, recovery) = result else {
            return XCTFail("Recovery reports the original operation as failed")
        }
        XCTAssertEqual(recovery, .recovered)
        XCTAssertEqual(services.mover.restoreCount, 1)
        let storedJournal = await services.store.loadJournal()
        XCTAssertNil(storedJournal)
    }

    func testConflictAndMissingCapabilitiesFailWithoutInput() async {
        let unsupported = observation(placement: .menuBar, capabilities: [.discover, .observe])
        let services = Services(original: unsupported)
        services.conflict.hasConflict = true
        let coordinator = services.makeCoordinator()
        await coordinator.load()
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)

        let conflict = await coordinator.moveToDrawer(unsupported.id)
        XCTAssertEqual(
            conflict,
            .failed(
                message: "Another menu-bar change was detected. No item was moved.",
                recovery: .recovered
            )
        )
        services.conflict.hasConflict = false
        let capability = await coordinator.moveToDrawer(unsupported.id)
        guard case let .failed(message, _) = capability else {
            return XCTFail("Expected capability failure")
        }
        XCTAssertTrue(message.contains("not supported"))
        XCTAssertEqual(services.mover.moveCount, 0)
    }

    func testDisableRestoresEveryManagedItemBeforePersistingDisabledState() async {
        let original = observation(placement: .menuBar)
        let services = Services(original: original)
        let coordinator = services.makeCoordinator()
        await coordinator.load()
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)
        _ = await coordinator.moveToDrawer(original.id)

        let disabled = await coordinator.setExternalManagementEnabled(false)

        XCTAssertTrue(disabled)
        XCTAssertFalse(coordinator.configuration.externalManagementEnabled)
        XCTAssertEqual(coordinator.configuration.items.first?.desiredPlacement, .menuBar)
        XCTAssertEqual(services.mover.restoreCount, 0)
        XCTAssertEqual(services.mover.moveCount, 2)
    }

    func testActivationRequiresOptInAndCapability() async {
        let original = observation(placement: .drawer)
        let services = Services(original: original)
        let coordinator = services.makeCoordinator()
        await coordinator.load()
        let request = DrawerActivationRequest(itemID: original.id, event: nil)

        _ = await coordinator.activate(request)
        XCTAssertEqual(services.activator.activationCount, 0)
        let enabled = await coordinator.setExternalManagementEnabled(true)
        XCTAssertTrue(enabled)
        let result = await coordinator.activate(request)

        guard case .succeeded = result else { return XCTFail("Expected activation") }
        XCTAssertEqual(services.activator.activationCount, 1)
    }

    func testManagedIdentitySeparatesTwoItemsFromSameApplication() {
        let first = itemID(semanticIdentifier: "primary")
        let second = itemID(semanticIdentifier: "secondary")

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first.persistenceKey, second.persistenceKey)
    }

    func testFileStoreRoundTripAndRejectsUnsafeFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDrawerStateStore(directory: root)
        var configuration = DrawerConfiguration.defaults
        configuration.externalManagementEnabled = true
        configuration.setPlacement(.drawer, for: itemID())
        let operation = journal(original: observation(placement: .menuBar))

        try await store.saveConfiguration(configuration)
        try await store.saveJournal(operation)
        let loadedConfiguration = try await store.loadConfiguration()
        let loadedJournal = try await store.loadJournal()
        XCTAssertEqual(loadedConfiguration, configuration)
        XCTAssertEqual(loadedJournal?.operationID, operation.operationID)
        XCTAssertEqual(loadedJournal?.requestedPlacement, operation.requestedPlacement)
        XCTAssertEqual(loadedJournal?.original, operation.original)
        XCTAssertEqual(loadedJournal?.phase, operation.phase)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: root.appending(path: "configuration.json").path
            )[.posixPermissions] as? Int,
            0o600
        )

        try await store.removeJournal()
        let removedJournal = try await store.loadJournal()
        XCTAssertNil(removedJournal)
        let target = root.appending(path: "target")
        try Data("{}".utf8).write(to: target)
        let link = root.appending(path: "operation-journal.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            _ = try await store.loadJournal()
            XCTFail("Expected an unsafe journal file to be rejected")
        } catch { }
    }

    private func itemID(semanticIdentifier: String = "com.apple.menuextra.wifi")
        -> ManagedMenuBarItemID {
        ManagedMenuBarItemID(
            source: .system,
            ownerBundleIdentifier: "com.apple.controlcenter",
            semanticIdentifier: semanticIdentifier
        )
    }

    private func observation(
        placement: DrawerPlacement,
        capabilities: DrawerItemCapabilities = .externallyManaged
    ) -> DrawerItemObservation {
        DrawerItemObservation(
            id: itemID(),
            capabilities: capabilities,
            placement: placement,
            screenIdentifier: "fixture-screen",
            leadingAnchorID: nil,
            trailingAnchorID: nil,
            x: 100,
            y: 0,
            width: 24,
            height: 24
        )
    }

    private func journal(original: DrawerItemObservation) -> DrawerOperationJournal {
        DrawerOperationJournal(
            version: DrawerOperationJournal.currentVersion,
            operationID: UUID(),
            createdAt: .now,
            requestedPlacement: .drawer,
            original: original,
            observed: nil,
            phase: .prepared,
            failure: "fixture"
        )
    }
}

private extension DrawerCoordinatorTests {
    struct Services {
        let discovery: DrawerDiscoveryStub
        let mover: DrawerMoverStub
        let activator = DrawerActivatorStub()
        let observer: DrawerObserverStub
        let conflict = DrawerConflictStub()
        let store = DrawerStoreStub()

        @MainActor
        init(original: DrawerItemObservation) {
            observer = DrawerObserverStub(observation: original)
            discovery = DrawerDiscoveryStub(items: [original])
            mover = DrawerMoverStub(observer: observer)
        }

        @MainActor
        func makeCoordinator() -> DrawerCoordinator {
            DrawerCoordinator(
                discovery: discovery,
                mover: mover,
                activator: activator,
                observer: observer,
                conflictDetector: conflict,
                stateStore: store
            )
        }
    }

    enum FixtureError: Error {
        case restoreFailed
    }
}

@MainActor
private final class DrawerDiscoveryStub: ExternalMenuBarItemDiscovering {
    var items: [DrawerItemObservation]
    init(items: [DrawerItemObservation]) { self.items = items }
    func discoverItems() async throws -> [DrawerItemObservation] { items }
}

@MainActor
private final class DrawerObserverStub: ExternalMenuBarItemObserving {
    var current: DrawerItemObservation
    var forcedPlacementAfterMove: DrawerPlacement?
    init(observation: DrawerItemObservation) { current = observation }
    func observation(for id: ManagedMenuBarItemID) async throws -> DrawerItemObservation? {
        current.id == id ? current : nil
    }
}

@MainActor
private final class DrawerMoverStub: ExternalMenuBarItemMoving {
    let observer: DrawerObserverStub
    var moveCount = 0
    var restoreCount = 0
    var restoreError: Error?
    init(observer: DrawerObserverStub) { self.observer = observer }

    func move(_ item: DrawerItemObservation, to placement: DrawerPlacement) async throws {
        moveCount += 1
        observer.current = DrawerItemObservation(
            id: item.id,
            capabilities: item.capabilities,
            placement: observer.forcedPlacementAfterMove ?? placement,
            screenIdentifier: item.screenIdentifier,
            leadingAnchorID: item.leadingAnchorID,
            trailingAnchorID: item.trailingAnchorID,
            x: item.x,
            y: item.y,
            width: item.width,
            height: item.height
        )
    }

    func restore(_ item: DrawerItemObservation) async throws {
        restoreCount += 1
        if let restoreError { throw restoreError }
        observer.current = item
    }
}

@MainActor
private final class DrawerActivatorStub: ExternalMenuBarItemActivating {
    var activationCount = 0
    func activate(_ request: DrawerActivationRequest) async throws { activationCount += 1 }
}

@MainActor
private final class DrawerConflictStub: MenuBarConflictDetecting {
    var hasConflict = false
    func hasConflict(in observations: [DrawerItemObservation]) async -> Bool { hasConflict }
}

private actor DrawerStoreStub: DrawerStateStoring {
    var configuration = DrawerConfiguration.defaults
    var journal: DrawerOperationJournal?
    var savedJournalPhases: [DrawerOperationJournal.Phase] = []

    func loadConfiguration() -> DrawerConfiguration { configuration }
    func saveConfiguration(_ configuration: DrawerConfiguration) { self.configuration = configuration }
    func loadJournal() -> DrawerOperationJournal? { journal }
    func saveJournal(_ journal: DrawerOperationJournal) {
        self.journal = journal
        savedJournalPhases.append(journal.phase)
    }
    func removeJournal() { journal = nil }
}
