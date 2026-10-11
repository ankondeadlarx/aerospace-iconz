public enum PauseReason: Hashable, Sendable {
    case displaysAsleep, screenLocked
}

public enum BarState: Equatable, Sendable {
    case unavailable
    /// `mode` is the binding mode, `nil` when unknown.
    case workspaces([WorkspaceGroup], mode: String? = nil)
}

/// Decides when to re-read AeroSpace and publishes the result when it changes.
///
/// - Every event (or `nudge()`) starts a burst: refresh now, then at each `burstDelays` offset.
///   A newer event restarts the burst.
/// - A slow poll covers changes AeroSpace has no event for. It stops entirely while any
///   `PauseReason` holds, and resuming refreshes at once.
/// - Refreshes never overlap: a request during one in flight runs once more afterwards.
/// - The binding mode is read alongside every refresh except the poll's: each mode change
///   fires an event, so the poll can reuse the last mode and spare a CLI call every interval.
///   After a failed snapshot, the next refresh of any kind reads it again. A failed mode read
///   alone waits for the next event, so a mode that can't be read never costs a call per poll.
@MainActor
public final class RefreshCoordinator {
    private let client: any AeroSpaceClient
    private let timing: Timing
    private let clock: any MonotonicClock
    private let publish: @MainActor (BarState) -> Void

    private var reducer = WorkspaceReducer()
    /// From the last good read; tells an icon click which windows its app has. Not part of
    /// `BarState`, so windows coming and going don't redraw.
    private var windows: [WindowInfo] = []
    private var mode: String?
    /// The next refresh must read the mode, even the poll's.
    private var modeIsStale = true
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

    /// A left-click on the bar.
    public func select(_ target: ClickTarget) async {
        switch target {
        case .workspace(let name): await focus(workspace: name)
        case .app(let app, let workspace): await focus(app: app, on: workspace)
        }
    }

    public func focus(workspace: WorkspaceName) async {
        try? await client.focus(workspace: workspace)
        nudge()
    }

    /// An icon click: focuses `app`'s oldest window on `workspace`, or its next one there if
    /// one of them already has focus. Switches to the workspace if that can't be done.
    public func focus(app: AppKey, on workspace: WorkspaceName) async {
        let ids = windows.filter { $0.workspace == workspace && $0.appKey == app }.map(\.id).sorted()
        do {
            guard let target = await nextWindow(among: ids) else { throw NoWindow() }
            try await client.focus(windowId: target)
            nudge()
        } catch {
            await focus(workspace: workspace)
        }
    }

    private struct NoWindow: Error {}

    /// The window after the focused one in `ids` (wrapping), else the first.
    private func nextWindow(among ids: [Int]) async -> Int? {
        guard let first = ids.first else { return nil }
        guard let focused = try? await client.focusedWindowId(), let index = ids.firstIndex(of: focused) else {
            return first
        }
        return ids[(index + 1) % ids.count]
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
        await refresh(readingMode: true)
    }

    func refresh(readingMode: Bool) async {
        if readingMode { modeIsStale = true }
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let readsMode = modeIsStale
            modeIsStale = false
            let state: BarState
            do {
                async let modeRead = readsMode ? readMode() : nil
                let snapshot = try await client.snapshot()
                windows = snapshot.windows
                switch await modeRead {
                case .success(let current)?:
                    mode = current
                case .failure(let error)?:
                    // Only decides the badge: a failed read hides it, not the whole bar.
                    if error is CancellationError { modeIsStale = true } else { mode = nil }
                case nil:
                    break
                }
                state = .workspaces(reducer.groups(for: snapshot), mode: mode)
            } catch is CancellationError {
                if readsMode { modeIsStale = true }
                continue
            } catch {
                modeIsStale = true
                state = .unavailable
            }
            if state != lastState {
                lastState = state
                publish(state)
            }
        } while refreshPending
    }

    private func readMode() async -> Result<String?, any Error> {
        do { return .success(try await client.mode()) } catch { return .failure(error) }
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
            await refresh(readingMode: false)
        }
    }
}
