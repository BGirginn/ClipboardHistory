import Foundation

extension ClipboardHistoryViewModel {
    func invalidatePendingCaptures() {
        captureGeneration &+= 1
    }

    func captureIsCurrent(_ generation: UInt) -> Bool {
        generation == captureGeneration && !Task.isCancelled && !isPaused && !isShuttingDown && !isClearingHistory
    }

    func finishCaptureMutation() {
        activeCaptureMutations -= 1
        guard activeCaptureMutations == 0 else { return }
        let waiters = captureDrainWaiters
        captureDrainWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func drainCaptureMutations() async {
        guard activeCaptureMutations > 0 else { return }
        await withCheckedContinuation { captureDrainWaiters.append($0) }
    }

    func discardCancelledCapture(_ item: ClipboardItem) async {
        do {
            let outcome = try await storage.deleteItem(item)
            if outcome.requiresCleanupRetry {
                cleanupMessage = String(localized: "Cancelled capture cleanup needs to be retried.")
            }
        } catch {
            errorMessage = String(localized: "Cancelled capture cleanup needs to be retried.")
        }
    }

    func toggleSearch() {
        isSearchVisible.toggle()
        if !isSearchVisible { searchText = "" }
    }
}
