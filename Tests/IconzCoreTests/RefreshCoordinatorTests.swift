import Testing
@testable import IconzCore

private struct Unreachable: Error {}

/// Scripted AeroSpace: returns whatever `current` is, or throws while `reachable` is false.
private final class FakeClient: AeroSpaceClient, @unchecked Sendable {
    var current = Snapshot(workspaces: [WorkspaceInfo(name: "1", isFocused: true, isVisible: true, monitorId: 1)], windows: [])
    var reachable = true
    private(set) var snapshotCalls = 0
    private(set) var focused: [String] = []

    func snapshot() async throws -> Snapshot {
        snapshotCalls += 1
        guard reachable else { throw Unreachable() }
        return current
    }

    func events() -> AsyncStream<AeroSpaceEvent> { AsyncStream { $0.finish() } }

    func focus(workspace: String) async throws { focused.append(workspace) }
}

/// Records requested sleeps and returns immediately.
private final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private(set) var slept: [Duration] = []
    func sleep(for duration: Duration) async throws { slept.append(duration) }
}

@MainActor
private func makeCoordinator(_ client: FakeClient, sleeper: RecordingSleeper = RecordingSleeper()) -> (RefreshCoordinator, Box) {
    let box = Box()
    let coordinator = RefreshCoordinator(client: client, timing: Config.standard.timing, sleeper: sleeper) { box.states.append($0) }
    return (coordinator, box)
}

@MainActor private final class Box { var states: [BarState] = [] }

@MainActor @Suite struct RefreshCoordinatorTests {
    @Test func firstRefreshPublishesGroups() async {
        let client = FakeClient()
        let (coordinator, box) = makeCoordinator(client)
        await coordinator.refresh()
        #expect(box.states == [.workspaces([WorkspaceGroup(name: "1", isFocused: true, isVisible: true, apps: [])])])
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
        let sleeper = RecordingSleeper()
        let (coordinator, _) = makeCoordinator(client, sleeper: sleeper)
        try await coordinator.burst()
        #expect(client.snapshotCalls == 3)
        // Follow-ups at +100 ms and +500 ms after the event.
        #expect(sleeper.slept == [.milliseconds(100), .milliseconds(400)])
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
