import Observation

/// Coalesces automatic checks and serializes forced checks for one feed.
@Observable
@MainActor
final class SyncQueue {
    private(set) var isRunning = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func run(force: Bool, operation: @escaping @MainActor () async -> Void) async {
        if let pending, !force {
            await pending.value
            return
        }

        // Reserve the successor before awaiting so forced requests form a
        // serial chain and keep the reminder busy through each handoff.
        let predecessor = pending
        generation += 1
        let currentGeneration = generation
        isRunning = true
        let task = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            await operation()
        }
        pending = task
        await task.value
        if generation == currentGeneration {
            pending = nil
            isRunning = false
        }
    }
}
