public enum PauseReason: Hashable, Sendable {
    case displaysAsleep, screenLocked
}

public enum BarState: Equatable, Sendable {
    case unavailable
    case workspaces([WorkspaceGroup])
}

/// Decides when to re-read AeroSpace and publishes the result when it changes.
///
/// - Every event (or `nudge()`) starts a burst: refresh now, then at each `burstDelays` offset.
///   A newer event restarts the burst.
/// - A slow poll covers changes AeroSpace has no event for. It stops entirely while any
///   `PauseReason` holds, and resuming refreshes at once.
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
    private var pauseReasons: Set<PauseReason> = []
    private(set) var burstTask: Task<Void, Never>?
    // These hold the coordinator until `stop()` cancels them.
    private var subscriptionTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

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
        subscriptionTask = Task { await subscriptionLoop() }
        if pauseReasons.isEmpty { startPolling() }
        nudge()
    }

    public func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        pollTask?.cancel()
        pollTask = nil
        burstTask?.cancel()
    }

    /// Something may have changed: refresh now and again shortly after.
    public func nudge() {
        burstTask?.cancel()
        burstTask = Task { [weak self] in try? await self?.burst() }
    }

    /// Stops the poll while any reason holds. Events still refresh.
    public func setPaused(_ paused: Bool, for reason: PauseReason) {
        let wasPaused = !pauseReasons.isEmpty
        if paused { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        let isPaused = !pauseReasons.isEmpty
        guard isPaused != wasPaused, subscriptionTask != nil else { return }
        if isPaused {
            pollTask?.cancel()
            pollTask = nil
        } else {
            startPolling()
            nudge()
        }
    }

    public func focus(workspace: WorkspaceName) async {
        try? await client.focus(workspace: workspace)
        nudge()
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
            } catch is CancellationError {
                continue
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

    private func startPolling() {
        pollTask = Task { await pollLoop() }
    }

    private func pollLoop() async {
        while true {
            do { try await clock.sleep(for: timing.pollInterval) } catch { return }
            await refresh()
        }
    }
}
