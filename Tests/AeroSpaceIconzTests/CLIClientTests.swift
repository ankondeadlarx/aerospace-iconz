import Foundation
import IconzCore
import Testing
@testable import AeroSpaceIconz

/// Writes a stand-in `aerospace` script that answers the commands `CLIClient` sends.
/// `subscribe` prints two events, then exits or (if `subscriptionStaysAlive`) keeps running.
private func fakeAerospace(subscriptionStaysAlive: Bool = false) throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("aerospace").path
    let script = """
    #!/bin/sh
    case "$1" in
      list-windows) echo '[{"app-bundle-id":"a.b","app-name":"A","app-pid":1,"window-id":5,"workspace":"1"}]' ;;
      list-workspaces) echo '[{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true}]' ;;
      workspace) [ "$2" = "1" ] || exit 1 ;;
      subscribe)
        echo '{"_event":"focus-changed","workspace":"1"}'
        echo '{"_event":"mode-changed","mode":"main"}'
        \(subscriptionStaysAlive ? "exec sleep 30" : "") ;;
    esac
    """
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

// Serialized: `Subscriptions` is process-wide, so counts would mix across parallel tests.
@Suite(.serialized) struct CLIClientTests {
    @Test func snapshotParsesBothListCommands() async throws {
        let client = CLIClient(candidates: [try fakeAerospace()])
        let snapshot = try await client.snapshot()
        #expect(snapshot == Snapshot(
            workspaces: [WorkspaceInfo(name: "1", isFocused: true, isVisible: true)],
            windows: [WindowInfo(id: 5, appBundleId: "a.b", appName: "A", appPid: 1, workspace: "1")]
        ))
    }

    @Test func focusSucceedsWhenTheCommandDoes() async throws {
        let client = CLIClient(candidates: [try fakeAerospace()])
        try await client.focus(workspace: "1")
    }

    @Test func focusThrowsWhenTheCommandFails() async throws {
        let client = CLIClient(candidates: [try fakeAerospace()])
        await #expect(throws: CLIError.self) { try await client.focus(workspace: "9") }
    }

    @Test func eventsYieldsEachLineAndEndsWhenTheProcessExits() async throws {
        let client = CLIClient(candidates: [try fakeAerospace()])
        var count = 0
        for await _ in client.events() { count += 1 }
        #expect(count == 2)
        #expect(Subscriptions.liveCount == 0)
    }

    @Test func terminateAllEndsALiveSubscription() async throws {
        let client = CLIClient(candidates: [try fakeAerospace(subscriptionStaysAlive: true)])
        let start = ContinuousClock.now
        var count = 0
        for await _ in client.events() {
            count += 1
            if count == 1 {
                #expect(Subscriptions.liveCount == 1)
                Subscriptions.terminateAll()
            }
        }
        // Ended because it was killed, not because the fake's 30 s sleep ran out.
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(Subscriptions.liveCount == 0)
    }

    @Test func subscriptionThatFailsToLaunchIsNotTracked() async {
        let client = CLIClient(candidates: ["/nonexistent/aerospace"])
        for await _ in client.events() {}
        #expect(Subscriptions.liveCount == 0)
    }
}
