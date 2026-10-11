import Synchronization
import Testing
@testable import IconzCore

private struct Unreachable: Error {}

/// Scripted AeroSpace: returns whatever `current` is, or throws `failure` when set.
/// Each `events()` call opens a subscription the test feeds with `emit()` and ends with
/// `endSubscription()`.
private final class FakeClient: AeroSpaceClient, Sendable {
    private struct State {
        var current = Snapshot(workspaces: [WorkspaceInfo(name: "1", isFocused: true, isVisible: true)], windows: [])
        var failure: (any Error & Sendable)?
        var clock: FakeClock?
        var snapshotCalls = 0
        var mode: String?
        var modeFailure: (any Error & Sendable)?
        var modeCalls = 0
        var focused: [WorkspaceName] = []
        var subscriptions: [AsyncStream<AeroSpaceEvent>.Continuation] = []
        var endedSubscriptions = 0
        var isHolding = false
        var held: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var current: Snapshot {
        get { state.withLock { $0.current } }
        set { state.withLock { $0.current = newValue } }
    }
    var failure: (any Error & Sendable)? {
        get { state.withLock { $0.failure } }
        set { state.withLock { $0.failure = newValue } }
    }
    /// When set, each snapshot takes 20 ms on this clock, like the real CLI.
    var clock: FakeClock? {
        get { state.withLock { $0.clock } }
        set { state.withLock { $0.clock = newValue } }
    }
    var snapshotCalls: Int { state.withLock { $0.snapshotCalls } }
    var mode: String? {
        get { state.withLock { $0.mode } }
        set { state.withLock { $0.mode = newValue } }
    }
    var modeFailure: (any Error & Sendable)? {
        get { state.withLock { $0.modeFailure } }
        set { state.withLock { $0.modeFailure = newValue } }
    }
    var modeCalls: Int { state.withLock { $0.modeCalls } }
    var focused: [WorkspaceName] { state.withLock { $0.focused } }
    var subscriptionCount: Int { state.withLock { $0.subscriptions.count } }
    var openSubscriptionCount: Int { state.withLock { $0.subscriptions.count - $0.endedSubscriptions } }

    func snapshot() async throws -> Snapshot {
        let (result, failure, clock, hold) = state.withLock { s in
            s.snapshotCalls += 1
            return (s.current, s.failure, s.clock, s.isHolding)
        }
        clock?.advance(by: .milliseconds(20))
        if hold {
            await withCheckedContinuation { continuation in state.withLock { $0.held.append(continuation) } }
        }
        if let failure { throw failure }
        return result
    }

    func mode() async throws -> String? {
        let (mode, failure) = state.withLock { s in
            s.modeCalls += 1
            return (s.mode, s.modeFailure)
        }
        if let failure { throw failure }
        return mode
    }

    func events() -> AsyncStream<AeroSpaceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: AeroSpaceEvent.self)
        continuation.onTermination = { [state = self] _ in state.subscriptionEnded() }
        state.withLock { $0.subscriptions.append(continuation) }
        return stream
    }

    func focus(workspace: WorkspaceName) async throws { state.withLock { $0.focused.append(workspace) } }

    private func subscriptionEnded() { state.withLock { $0.endedSubscriptions += 1 } }

    func emit() { _ = state.withLock { $0.subscriptions.last }?.yield(AeroSpaceEvent()) }
    func endSubscription() { state.withLock { $0.subscriptions.last }?.finish() }

    /// Snapshots started from now on wait for `releaseSnapshots()`.
    func holdSnapshots() { state.withLock { $0.isHolding = true } }
    func releaseSnapshots() {
        let held = state.withLock { s in
            s.isHolding = false
            defer { s.held = [] }
            return s.held
        }
        held.forEach { $0.resume() }
    }
}

/// Time only moves when told to. Sleeping jumps straight to the deadline and records it.
private final class FakeClock: MonotonicClock, @unchecked Sendable {
    private var time = Duration.zero
    private(set) var deadlines: [Duration] = []

    func now() -> Duration { time }
    func advance(by duration: Duration) { time += duration }

    func sleep(until deadline: Duration) async throws {
        deadlines.append(deadline)
        time = max(time, deadline)
    }
}

/// Time only moves when the test advances it; sleepers stay suspended until their deadline
/// has passed, or until cancelled. For driving the coordinator's long-running loops.
private final class ManualClock: MonotonicClock, Sendable {
    private struct Sleeper {
        var id: Int
        var deadline: Duration
        var continuation: CheckedContinuation<Void, any Error>
    }
    private struct State {
        var time = Duration.zero
        var nextId = 0
        var sleepers: [Sleeper] = []
    }

    private let state = Mutex(State())

    func now() -> Duration { state.withLock { $0.time } }
    var pendingDeadlines: [Duration] { state.withLock { $0.sleepers.map(\.deadline) } }

    func advance(by duration: Duration) {
        let due = state.withLock { s in
            s.time += duration
            let now = s.time
            defer { s.sleepers.removeAll { $0.deadline <= now } }
            return s.sleepers.filter { $0.deadline <= now }
        }
        due.forEach { $0.continuation.resume() }
    }

    func sleep(until deadline: Duration) async throws {
        let id = state.withLock { s in
            s.nextId += 1
            return s.nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Checked under the lock so a cancel racing with this registration can't be lost.
                let wake: Result<Void, any Error>? = state.withLock { s in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= s.time { return .success(()) }
                    s.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return nil
                }
                if let wake { continuation.resume(with: wake) }
            }
        } onCancel: {
            let sleeper = state.withLock { s -> Sleeper? in
                guard let index = s.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return s.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }
}

@MainActor private final class Published { var states: [BarState] = [] }

/// The group for `FakeClient`'s default snapshot.
private let focusedOne = WorkspaceGroup(workspace: WorkspaceInfo(name: "1", isFocused: true, isVisible: true), apps: [])

@MainActor
private func makeCoordinator(
    _ client: FakeClient, clock: any MonotonicClock = FakeClock(), timing: Timing = Config.standard.timing
) -> (RefreshCoordinator, Published) {
    let published = Published()
    let coordinator = RefreshCoordinator(client: client, timing: timing, clock: clock) { published.states.append($0) }
    return (coordinator, published)
}

/// Waits (in real time, briefly) for work on other tasks to make `condition` true.
@MainActor
private func eventually(
    _ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition(), sourceLocation: sourceLocation)
}

@MainActor @Suite struct RefreshCoordinatorTests {
    @Test func firstRefreshPublishesGroups() async {
        let client = FakeClient()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        #expect(published.states == [.workspaces([WorkspaceGroup(workspace: WorkspaceInfo(name: "1", isFocused: true, isVisible: true), apps: [])])])
    }

    @Test func unchangedStateIsNotRepublished() async {
        let client = FakeClient()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        await coordinator.refresh()
        #expect(published.states.count == 1)
    }

    @Test func changedStateIsRepublished() async {
        let client = FakeClient()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        client.current.windows = [WindowInfo(id: 1, appBundleId: "a", appName: "A", appPid: 1, workspace: "1")]
        await coordinator.refresh()
        #expect(published.states.count == 2)
    }

    @Test func modeChangeAloneIsRepublished() async {
        let client = FakeClient()
        client.mode = "main"
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        client.mode = "service"
        await coordinator.refresh()
        #expect(published.states == [.workspaces([focusedOne], mode: "main"), .workspaces([focusedOne], mode: "service")])
    }

    @Test func refreshWithoutTheModeKeepsTheLastOne() async {
        let client = FakeClient()
        client.mode = "service"
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        client.mode = "main"
        await coordinator.refresh(readingMode: false)
        #expect(client.modeCalls == 1)
        #expect(published.states == [.workspaces([focusedOne], mode: "service")])
    }

    @Test func failedModeReadHidesTheBadgeUntilTheNextEvent() async {
        let client = FakeClient()
        client.mode = "service"
        client.modeFailure = Unreachable()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        #expect(published.states == [.workspaces([focusedOne], mode: nil)])
        // A mode read that keeps failing (e.g. an AeroSpace without `list-modes`) must not
        // add a CLI call to every poll.
        client.modeFailure = nil
        await coordinator.refresh(readingMode: false)
        #expect(client.modeCalls == 1)
        await coordinator.refresh()
        #expect(published.states.last == .workspaces([focusedOne], mode: "service"))
    }

    @Test func refreshAfterAFailedSnapshotReadsTheMode() async {
        let client = FakeClient()
        client.failure = Unreachable()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        client.failure = nil
        client.mode = "service"
        await coordinator.refresh(readingMode: false)
        #expect(published.states.last == .workspaces([focusedOne], mode: "service"))
    }

    @Test func unreachableAeroSpacePublishesUnavailableThenRecovers() async {
        let client = FakeClient()
        client.failure = Unreachable()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        await coordinator.refresh()
        client.failure = nil
        await coordinator.refresh()
        #expect(published.states.count == 2)
        #expect(published.states.first == .unavailable)
        #expect(published.states.last != .unavailable)
    }

    @Test func cancelledSnapshotKeepsTheCurrentState() async {
        let client = FakeClient()
        let (coordinator, published) = makeCoordinator(client)
        await coordinator.refresh()
        client.failure = CancellationError()
        await coordinator.refresh()
        #expect(published.states.count == 1)
        #expect(!published.states.contains(.unavailable))
    }

    @Test func refreshRequestedMidFlightRunsOnceMoreAfterwards() async {
        let client = FakeClient()
        let (coordinator, published) = makeCoordinator(client)
        client.holdSnapshots()
        let first = Task { await coordinator.refresh() }
        await eventually { client.snapshotCalls == 1 }

        // Changes during the first read; the requests below must not be lost, nor each run.
        client.current.windows = [WindowInfo(id: 1, appBundleId: "a", appName: "A", appPid: 1, workspace: "1")]
        await coordinator.refresh()
        await coordinator.refresh()
        client.releaseSnapshots()
        await first.value

        #expect(client.snapshotCalls == 2)
        guard case .workspaces(let groups, _) = published.states.last else {
            Issue.record("expected workspaces, got \(published.states)")
            return
        }
        #expect(groups.first?.apps.map(\.key.rawValue) == ["a"])
    }

    @Test func burstRefreshesNowThenAtEachFollowUp() async throws {
        let client = FakeClient()
        let (coordinator, _) = makeCoordinator(client)
        try await coordinator.burst()
        #expect(client.snapshotCalls == 3)
    }

    @Test func followUpsAreTimedFromTheEventNotFromTheEndOfEachRefresh() async throws {
        let clock = FakeClock()
        clock.advance(by: .seconds(7))
        let client = FakeClient()
        client.clock = clock
        let (coordinator, _) = makeCoordinator(client, clock: clock)
        try await coordinator.burst()
        // Each refresh takes 20 ms, but the follow-ups still land at +100 ms and +500 ms.
        #expect(clock.deadlines == [.seconds(7) + .milliseconds(100), .seconds(7) + .milliseconds(500)])
    }

    @Test func focusSwitchesThenRunsOneBurst() async {
        let client = FakeClient()
        let (coordinator, _) = makeCoordinator(client)
        await coordinator.focus(workspace: "2")
        await coordinator.burstTask?.value
        #expect(client.focused == ["2"])
        #expect(client.snapshotCalls == 3)
    }

    @Test func reconnectBackoffGrowsAndCaps() {
        let timing = Config.standard.timing
        #expect(timing.reconnectDelay(attempt: 0) == .seconds(1))
        #expect(timing.reconnectDelay(attempt: 1) == .seconds(2))
        #expect(timing.reconnectDelay(attempt: 50) == .seconds(10))
    }
}

/// The long-running parts started by `start()`: subscription, reconnect, poll, pause.
@MainActor @Suite struct RefreshCoordinatorLoopTests {
    /// A long poll, so its sleeps (≥ 60 s) are easy to tell from bursts (≤ 500 ms) and backoff (≤ 5 s).
    let timing = Timing(
        burstDelays: [.milliseconds(100), .milliseconds(500)],
        pollInterval: .seconds(60),
        reconnectBackoff: [.seconds(1), .seconds(2), .seconds(5)]
    )

    private func pollIsPending(_ clock: ManualClock) -> Bool {
        clock.pendingDeadlines.contains { $0 - clock.now() >= .seconds(30) }
    }

    private func start(_ client: FakeClient, _ clock: ManualClock) async -> RefreshCoordinator {
        let (coordinator, _) = makeCoordinator(client, clock: clock, timing: timing)
        coordinator.start()
        await eventually { client.subscriptionCount == 1 }
        return coordinator
    }

    @Test func endedSubscriptionReconnectsAfterBackoff() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }

        client.endSubscription()
        await eventually { clock.pendingDeadlines.contains(.seconds(1)) }
        #expect(client.subscriptionCount == 1)
        clock.advance(by: .seconds(1))
        await eventually { client.subscriptionCount == 2 }
    }

    @Test func backoffGrowsAcrossFailuresAndResetsAfterAnEvent() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }

        client.endSubscription()  // 1st failure: wait 1 s
        await eventually { clock.pendingDeadlines.contains(.seconds(1)) }
        clock.advance(by: .seconds(1))
        await eventually { client.subscriptionCount == 2 }

        client.endSubscription()  // 2nd in a row: wait 2 s
        await eventually { clock.pendingDeadlines.contains(.seconds(3)) }
        clock.advance(by: .seconds(2))
        await eventually { client.subscriptionCount == 3 }

        client.emit()             // connected for real, so the next failure starts over at 1 s
        client.endSubscription()
        await eventually { clock.pendingDeadlines.contains(.seconds(4)) }
    }

    @Test func newerEventRestartsTheBurst() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }
        await eventually { clock.pendingDeadlines.contains(.milliseconds(100)) }

        clock.advance(by: .milliseconds(50))
        client.emit()
        await eventually { clock.pendingDeadlines.contains(.milliseconds(150)) }
        #expect(!clock.pendingDeadlines.contains(.milliseconds(100)))
        #expect(!clock.pendingDeadlines.contains(.milliseconds(500)))
    }

    @Test func pollRefreshesEveryInterval() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }

        clock.advance(by: .milliseconds(600))  // let the start-up burst finish
        await eventually { client.snapshotCalls == 3 }
        clock.advance(by: .seconds(60) - .milliseconds(600))
        await eventually { client.snapshotCalls == 4 }
        await eventually { clock.pendingDeadlines.contains(.seconds(120)) }
    }

    @Test func eventReadsTheMode() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }
        clock.advance(by: .milliseconds(600))  // let the start-up burst finish
        await eventually { client.modeCalls == 3 }

        client.emit()  // e.g. `mode-changed`
        await eventually { client.modeCalls == 4 }
    }

    @Test func pollDoesNotReadTheMode() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }

        clock.advance(by: .milliseconds(600))  // the start-up burst reads it each time
        await eventually { client.snapshotCalls == 3 }
        #expect(client.modeCalls == 3)
        clock.advance(by: .seconds(60) - .milliseconds(600))
        await eventually { client.snapshotCalls == 4 }
        #expect(client.modeCalls == 3)
    }

    @Test func pausingStopsThePollAndResumingRefreshesAtOnce() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }
        await eventually { pollIsPending(clock) && client.snapshotCalls >= 1 }

        coordinator.setPaused(true, for: .displaysAsleep)
        #expect(!pollIsPending(clock))

        let calls = client.snapshotCalls
        coordinator.setPaused(false, for: .displaysAsleep)
        await eventually { client.snapshotCalls > calls }
        await eventually { pollIsPending(clock) }
    }

    @Test func pauseHoldsUntilEveryReasonClears() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        defer { coordinator.stop() }
        await eventually { pollIsPending(clock) }

        coordinator.setPaused(true, for: .displaysAsleep)
        coordinator.setPaused(true, for: .screenLocked)
        coordinator.setPaused(false, for: .displaysAsleep)
        #expect(!pollIsPending(clock))

        coordinator.setPaused(false, for: .screenLocked)
        await eventually { pollIsPending(clock) }
    }

    @Test func pausedBeforeStartDoesNotPoll() async {
        let client = FakeClient(), clock = ManualClock()
        let (coordinator, _) = makeCoordinator(client, clock: clock, timing: timing)
        defer { coordinator.stop() }
        coordinator.setPaused(true, for: .screenLocked)
        coordinator.start()
        await eventually { client.subscriptionCount == 1 && client.snapshotCalls >= 1 }
        #expect(!pollIsPending(clock))
    }

    @Test func stopEndsEveryLoop() async {
        let client = FakeClient(), clock = ManualClock()
        let coordinator = await start(client, clock)
        await eventually { pollIsPending(clock) }
        coordinator.stop()
        await eventually { clock.pendingDeadlines.isEmpty }
        await eventually { client.openSubscriptionCount == 0 }
    }
}
