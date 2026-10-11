import Synchronization

public enum PauseReason: Hashable, Sendable {
    case displaysAsleep, screenLocked
}

public enum BarState: Equatable, Sendable {
    case unavailable
    /// `mode` is the binding mode, `nil` when unknown.
    case workspaces([WorkspaceGroup], mode: String? = nil)

    /// The apps on `workspace`'s pill, in the order shown; empty if it has no pill.
    public func iconOrder(of workspace: WorkspaceName) -> [AppKey] {
        guard case .workspaces(let groups, _) = self else { return [] }
        return groups.first { $0.workspace.name == workspace }?.apps.map(\.key) ?? []
    }
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
    /// Window menu titles longer than this are cut in the middle.
    private let maxTitleLength: Int

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
        maxTitleLength: Int,
        publish: @escaping @MainActor (BarState) -> Void
    ) {
        self.client = client
        self.timing = timing
        self.clock = clock
        self.maxTitleLength = maxTitleLength
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

    /// A left-click on a pill's label or icon.
    public func select(_ selection: Selection) async {
        switch selection {
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
        guard let target = await nextWindow(among: ids) else {
            await focus(workspace: workspace)
            return
        }
        await focus(windowId: target, on: workspace)
    }

    /// Focuses a window (a window menu row, or an icon's pick). Switches to `workspace` if
    /// that fails, e.g. because the window has closed since.
    public func focus(windowId: WindowId, on workspace: WorkspaceName) async {
        do {
            try await client.focus(windowId: windowId)
            nudge()
        } catch {
            await focus(workspace: workspace)
        }
    }

    /// The window menu for `workspace`, read now and never kept: its windows with titles in the
    /// pill's icon order, the focused one marked. Unreadable if the windows can't be read within
    /// `windowMenuTimeout`; an unreadable focus only loses the mark.
    public func windowMenu(for workspace: WorkspaceName) async -> WindowMenu {
        let deadline = clock.now() + timing.windowMenuTimeout
        let client = client
        async let focused = withDeadline(deadline) { try await client.focusedWindowId() }
        guard case .success(let windows) = await withDeadline(deadline, { try await client.windows(on: workspace) }) else {
            // Waits for the focus read too (at most until the deadline): an `async let` must finish.
            _ = await focused
            return .unreadable(workspace)
        }
        return WindowMenu(
            workspace: workspace, windows: windows, iconOrder: lastState?.iconOrder(of: workspace) ?? [],
            focusedWindowId: try? await focused.get(), maxTitleLength: maxTitleLength
        )
    }

    private struct TimedOut: Error {}

    /// Races `work` against `deadline`: its result, or `TimedOut` if it hasn't finished by then.
    /// A late `work` keeps running (the CLI kills it at `cliTimeout`); its answer is dropped.
    private func withDeadline<T: Sendable>(
        _ deadline: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        let first = FirstToFinish<T>()
        var timer: Task<Void, Never>?
        let result = await withCheckedContinuation { continuation in
            first.wait(continuation)
            Task {
                do { first.resume(.success(try await work())) } catch { first.resume(.failure(error)) }
            }
            timer = Task { [clock] in
                guard (try? await clock.sleep(until: deadline)) != nil else { return }
                first.resume(.failure(TimedOut()))
            }
        }
        timer?.cancel()
        return result
    }

    /// The window after the focused one in `ids` (wrapping), else the first.
    private func nextWindow(among ids: [WindowId]) async -> WindowId? {
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

/// Resumes one continuation with whichever result arrives first; later ones are dropped.
private final class FirstToFinish<T: Sendable>: Sendable {
    private let continuation = Mutex<CheckedContinuation<Result<T, any Error>, Never>?>(nil)

    func wait(_ continuation: CheckedContinuation<Result<T, any Error>, Never>) {
        self.continuation.withLock { $0 = continuation }
    }

    func resume(_ result: Result<T, any Error>) {
        continuation.withLock { $0.take() }?.resume(returning: result)
    }
}
