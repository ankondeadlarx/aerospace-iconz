/// The one seam to AeroSpace. The app uses the CLI-backed implementation; tests use fakes.
public protocol AeroSpaceClient: Sendable {
    /// Current workspaces and windows. Throws if AeroSpace can't be reached.
    func snapshot() async throws -> Snapshot
    /// Live events. Finishes when the subscription dies (e.g. AeroSpace quit).
    func events() -> AsyncStream<AeroSpaceEvent>
    func focus(workspace: String) async throws
}

public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}
    public func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
