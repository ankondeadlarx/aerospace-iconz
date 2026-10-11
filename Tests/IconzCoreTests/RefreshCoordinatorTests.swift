import Testing
@testable import IconzCore

private struct Unreachable: Error {}

/// Scripted AeroSpace: returns whatever `current` is, or throws while `reachable` is false.
private final class FakeClient: AeroSpaceClient, @unchecked Sendable {
    var current = Snapshot(workspaces: [WorkspaceInfo(name: "1", isFocused: true, isVisible: true)], windows: [])
    var reachable = true
    /// When set, each snapshot takes 20 ms on this clock, like the real CLI.
    var clock: FakeClock?
    private(set) var snapshotCalls = 0
    private(set) var focused: [WorkspaceName] = []

    func snapshot() async throws -> Snapshot {
        snapshotCalls += 1
        clock?.advance(by: .milliseconds(20))
        guard reachable else { throw Unreachable() }
        return current
    }

    func events() -> AsyncStream<AeroSpaceEvent> { AsyncStream { $0.finish() } }

    func focus(workspace: WorkspaceName) async throws { focused.append(workspace) }
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

@MainActor
private func makeCoordinator(_ client: FakeClient, clock: FakeClock = FakeClock()) -> (RefreshCoordinator, Box) {
    let box = Box()
    let coordinator = RefreshCoordinator(client: client, timing: Config.standard.timing, clock: clock) { box.states.append($0) }
    return (coordinator, box)
}

@MainActor private final class Box { var states: [BarState] = [] }

@MainActor @Suite struct RefreshCoordinatorTests {
    @Test func firstRefreshPublishesGroups() async {
        let client = FakeClient()
        let (coordinator, box) = makeCoordinator(client)
        await coordinator.refresh()
        #expect(box.states == [.workspaces([WorkspaceGroup(workspace: WorkspaceInfo(name: "1", isFocused: true, isVisible: true), apps: [])])])
    }

    @Test func unchangedStateIsNotRepublished() async {
        let client = FakeClient()
        let (coordinator, box) = makeCoordinator(client)
        await coordinator.refresh()
        await coordinator.refresh()
        #expect(box.states.count == 1)
    }

    @Test func changedStateIsRepublished() async {
        let client = FakeClient()
        let (coordinator, box) = makeCoordinator(client)
        await coordinator.refresh()
        client.current.windows = [WindowInfo(id: 1, appBundleId: "a", appName: "A", appPid: 1, workspace: "1")]
        await coordinator.refresh()
        #expect(box.states.count == 2)
    }

    @Test func unreachableAeroSpacePublishesUnavailableThenRecovers() async {
        let client = FakeClient()
        client.reachable = false
        let (coordinator, box) = makeCoordinator(client)
        await coordinator.refresh()
        await coordinator.refresh()
        client.reachable = true
        await coordinator.refresh()
        #expect(box.states.count == 2)
        #expect(box.states.first == .unavailable)
        #expect(box.states.last != .unavailable)
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

    @Test func focusForwardsToClientAndRefreshes() async {
        let client = FakeClient()
        let (coordinator, _) = makeCoordinator(client)
        await coordinator.focus(workspace: "2")
        #expect(client.focused == ["2"])
        #expect(client.snapshotCalls >= 1)
    }

    @Test func reconnectBackoffGrowsAndCaps() {
        let timing = Config.standard.timing
        #expect(timing.reconnectDelay(attempt: 0) == .seconds(1))
        #expect(timing.reconnectDelay(attempt: 1) == .seconds(2))
        #expect(timing.reconnectDelay(attempt: 50) == .seconds(10))
    }
}
