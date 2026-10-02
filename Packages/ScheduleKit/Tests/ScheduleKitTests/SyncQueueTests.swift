import Testing
@testable import ScheduleKit

/// Gates keep request ordering deterministic without sleeps or network calls.
@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor
struct SyncQueueTests {
    @Test func automaticChecksShareThePendingOperationAndWaitForIt() async {
        let queue = SyncQueue()
        let started = Gate()
        let finish = Gate()
        let joined = Gate()
        var calls = 0
        var joinReturned = false
        let first = Task {
            await queue.run(force: false) {
                calls += 1
                started.open()
                await finish.wait()
            }
        }
        await started.wait()
        let second = Task {
            // The same actor reserves the request before the waiter resumes.
            joined.open()
            await queue.run(force: false) { calls += 1 }
            joinReturned = true
        }
        await joined.wait()
        #expect(queue.isRunning)
        #expect(calls == 1)
        #expect(!joinReturned)

        finish.open()
        await first.value
        await second.value
        #expect(calls == 1)
        #expect(joinReturned)
        #expect(!queue.isRunning)
    }

    @Test func forcedChecksRunInOrderAndStayBusyThroughEveryHandoff() async {
        let queue = SyncQueue()
        let started = (0..<3).map { _ in Gate() }
        let finish = (0..<3).map { _ in Gate() }
        var order: [Int] = []
        var active = 0
        func operation(_ index: Int) async {
            #expect(queue.isRunning)
            #expect(active == 0)
            active += 1
            order.append(index)
            started[index].open()
            await finish[index].wait()
            #expect(queue.isRunning)
            active -= 1
        }

        let first = Task { await queue.run(force: false) { await operation(0) } }
        await started[0].wait()
        let secondQueued = Gate()
        let second = Task {
            secondQueued.open()
            await queue.run(force: true) { await operation(1) }
        }
        await secondQueued.wait()
        let thirdQueued = Gate()
        let third = Task {
            thirdQueued.open()
            await queue.run(force: true) { await operation(2) }
        }
        await thirdQueued.wait()

        // An automatic check joins the tail, including queued manual checks.
        let joined = Gate()
        var joinReturned = false
        let automatic = Task {
            joined.open()
            await queue.run(force: false) { Issue.record("Automatic check should coalesce") }
            joinReturned = true
        }
        await joined.wait()
        #expect(order == [0])
        #expect(!joinReturned)

        finish[0].open()
        await started[1].wait()
        await first.value
        #expect(order == [0, 1])
        #expect(queue.isRunning)
        #expect(!joinReturned)

        finish[1].open()
        await started[2].wait()
        await second.value
        #expect(order == [0, 1, 2])
        #expect(queue.isRunning)
        #expect(!joinReturned)

        finish[2].open()
        await third.value
        await automatic.value
        #expect(active == 0)
        #expect(joinReturned)
        #expect(!queue.isRunning)
    }

    @Test func finishedQueueAcceptsNewAutomaticAndForcedChecks() async {
        let queue = SyncQueue()
        var calls = 0
        #expect(!queue.isRunning)
        for force in [false, true, false] {
            await queue.run(force: force) {
                #expect(queue.isRunning)
                calls += 1
            }
            #expect(!queue.isRunning)
        }
        #expect(calls == 3)
    }
}
