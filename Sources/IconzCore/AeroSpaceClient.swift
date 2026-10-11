/// The one seam to AeroSpace. The app uses the CLI-backed implementation; tests use fakes.
public protocol AeroSpaceClient: Sendable {
    /// Current workspaces and windows. Throws if AeroSpace can't be reached.
    func snapshot() async throws -> Snapshot
    /// The current binding mode (`"main"`, `"service"`, …), or `nil` if there is none.
    func mode() async throws -> String?
    /// Live events. Finishes when the subscription dies (e.g. AeroSpace quit).
    func events() -> AsyncStream<AeroSpaceEvent>
    func focus(workspace: WorkspaceName) async throws
}

/// Monotonic time as a `Duration` since an arbitrary origin, so tests can drive it.
public protocol MonotonicClock: Sendable {
    func now() -> Duration
    func sleep(until deadline: Duration) async throws
}

extension MonotonicClock {
    public func sleep(for duration: Duration) async throws {
        try await sleep(until: now() + duration)
    }
}

public struct SystemClock: MonotonicClock {
    private let origin = ContinuousClock.now

    public init() {}

    public func now() -> Duration { ContinuousClock.now - origin }

    public func sleep(until deadline: Duration) async throws {
        try await Task.sleep(until: origin + deadline, clock: .continuous)
    }
}
