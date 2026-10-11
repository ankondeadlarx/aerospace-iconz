public enum BarState: Equatable, Sendable {
    case unavailable
    case workspaces([WorkspaceGroup])
}

/// Decides when to re-read AeroSpace and publishes the result when it changes.
///
/// - Every event (or `nudge()`) starts a burst: refresh now, then at each `burstDelays` offset.
///   A newer event restarts the burst.
/// - A slow poll covers changes AeroSpace has no event for; it pauses while the screen sleeps.
/// - Refreshes never overlap: a request during one in flight runs once more afterwards.
@MainActor
public final class RefreshCoordinator {
    private let client: any AeroSpaceClient
    private let timing: Timing
    private let clock: any MonotonicClock
    private let publish: @MainActor (BarState) -> Void

    private var reducer = WorkspaceReducer()
    private var lastState: BarState?
    private var isRefreshing = false
    private var refreshPending = false
    private var isPaused = false
    private var burstTask: Task<Void, Never>?
    private var loops: [Task<Void, Never>] = []

    public init(
        client: any AeroSpaceClient, timing: Timing, clock: any MonotonicClock = SystemClock(),
        publish: @escaping @MainActor (BarState) -> Void
    ) {
        self.client = client
        self.timing = timing
        self.clock = clock
        self.publish = publish
    }

    public func start() {
        loops = [
            Task { [weak self] in await self?.subscriptionLoop() },
            Task { [weak self] in await self?.pollLoop() },
        ]
        nudge()
    }

    public func stop() {
        loops.forEach { $0.cancel() }
        loops = []
        burstTask?.cancel()
    }

    /// Something may have changed: refresh now and again shortly after.
    public func nudge() {
        burstTask?.cancel()
        burstTask = Task { [weak self] in try? await self?.burst() }
    }

    public func setPaused(_ paused: Bool) {
        isPaused = paused
        if !paused { nudge() }
    }

    public func focus(workspace: String) async {
        try? await client.focus(workspace: workspace)
        nudge()
        await refresh()
    }

    func burst() async throws {
        let event = clock.now()
        await refresh()
        for offset in timing.burstDelays {
            try await clock.sleep(until: event + offset)
            try Task.checkCancellation()
            await refresh()
        }
    }

    public func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let state: BarState
            do {
                state = .workspaces(reducer.groups(for: try await client.snapshot()))
            } catch {
                state = .unavailable
            }
            if state != lastState {
                lastState = state
                publish(state)
            }
        } while refreshPending
    }

    private func subscriptionLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            for await _ in client.events() {
                attempt = 0
                nudge()
            }
            // Subscription ended: AeroSpace quit or restarted. Show it, then reconnect.
            await refresh()
            try? await clock.sleep(for: timing.reconnectDelay(attempt: attempt))
            attempt += 1
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await clock.sleep(for: timing.pollInterval)
            if !isPaused { await refresh() }
        }
    }
}
