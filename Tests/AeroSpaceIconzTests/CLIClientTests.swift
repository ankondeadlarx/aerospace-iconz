import Foundation
import IconzCore
import Testing
@testable import AeroSpaceIconz

/// Writes a stand-in `aerospace` script that answers only the exact command lines
/// `CLIClient` should send (anything else exits 2, as if the flags were wrong).
/// `subscribe` prints two events, then exits or (if `subscriptionStaysAlive`) keeps running.
/// With `listCommandsHang`, the `list-*` commands never answer. With `modesFail`, only
/// `list-modes` fails.
private func fakeAerospace(
    subscriptionStaysAlive: Bool = false, listCommandsHang: Bool = false, modesFail: Bool = false
) throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("aerospace").path
    let hang = listCommandsHang ? "exec sleep 30;" : ""
    // `--format` is spelled out on purpose: without it, real `list-windows --json` omits
    // the bundle id and workspace.
    let script = """
    #!/bin/sh
    case "$*" in
      "list-windows --all --json --format %{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}")
        \(hang) echo '[{"app-bundle-id":"a.b","app-name":"A","app-pid":1,"window-id":5,"workspace":"1"}]' ;;
      "list-workspaces --all --json --format %{workspace} %{workspace-is-focused} %{workspace-is-visible}")
        \(hang) echo '[{"workspace":"1","workspace-is-focused":true,"workspace-is-visible":true}]' ;;
      "list-modes --current --json")
        \(hang) \(modesFail ? "exit 1;" : "") echo '[{"mode-id":"service"}]' ;;
      "list-windows --workspace 1 --json --format %{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{window-title}")
        echo '[{"app-bundle-id":"a.b","app-name":"A","app-pid":1,"window-id":5,"window-title":"Doc"}]' ;;
      "list-windows --focused --json --format %{window-id}")
        echo '[{"window-id":5}]' ;;
      "focus --window-id 5") ;;
      'focus --window-id '*) exit 1 ;;
      "workspace 1") ;;
      'workspace '*) exit 1 ;;
      "subscribe --all")
        echo '{"_event":"focus-changed","workspace":"1"}'
        echo '{"_event":"mode-changed","mode":"main"}'
        \(subscriptionStaysAlive ? "exec sleep 30" : "") ;;
      *) exit 2 ;;
    esac
    """
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

private func makeClient(_ path: String, timeout: Duration = .seconds(5)) -> CLIClient {
    CLIClient(candidates: [path], timeout: timeout)
}

// Serialized: `Subscriptions` is process-wide, so counts would mix across parallel tests.
@Suite(.serialized) struct CLIClientTests {
    @Test func snapshotParsesBothListCommands() async throws {
        let client = makeClient(try fakeAerospace())
        let snapshot = try await client.snapshot()
        #expect(snapshot == Snapshot(
            workspaces: [WorkspaceInfo(name: "1", isFocused: true, isVisible: true)],
            windows: [WindowInfo(id: 5, appBundleId: "a.b", appName: "A", appPid: 1, workspace: "1")]
        ))
    }

    @Test func modeReadsTheCurrentMode() async throws {
        let client = makeClient(try fakeAerospace())
        #expect(try await client.mode() == "service")
    }

    @Test func modeThrowsWhenListModesFails() async throws {
        let client = makeClient(try fakeAerospace(modesFail: true))
        await #expect(throws: CLIError.self) { try await client.mode() }
    }

    @Test func focusSucceedsWhenTheCommandDoes() async throws {
        let client = makeClient(try fakeAerospace())
        try await client.focus(workspace: "1")
    }

    @Test func focusThrowsWhenTheCommandFails() async throws {
        let client = makeClient(try fakeAerospace())
        await #expect(throws: CLIError.self) { try await client.focus(workspace: "9") }
    }

    @Test func focusedWindowIdReadsTheFocusedWindow() async throws {
        let client = makeClient(try fakeAerospace())
        #expect(try await client.focusedWindowId() == 5)
    }

    @Test func windowsOnAWorkspaceReadsTheirTitles() async throws {
        let client = makeClient(try fakeAerospace())
        #expect(try await client.windows(on: "1") == [
            TitledWindow(id: 5, appBundleId: "a.b", appName: "A", appPid: 1, title: "Doc"),
        ])
    }

    @Test func focusWindowSucceedsWhenTheCommandDoes() async throws {
        let client = makeClient(try fakeAerospace())
        try await client.focus(windowId: 5)
    }

    @Test func focusWindowThrowsWhenTheCommandFails() async throws {
        let client = makeClient(try fakeAerospace())
        await #expect(throws: CLIError.self) { try await client.focus(windowId: 6) }
    }

    @Test func snapshotGivesUpOnAHungCommand() async throws {
        let client = makeClient(try fakeAerospace(listCommandsHang: true), timeout: .milliseconds(300))
        let start = ContinuousClock.now
        await #expect(throws: CLIError.timedOut) { try await client.snapshot() }
        // Gave up at the timeout, not when the fake's 30 s sleep ran out.
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func eventsYieldsEachLineAndEndsWhenTheProcessExits() async throws {
        let client = makeClient(try fakeAerospace())
        var count = 0
        for await _ in client.events() { count += 1 }
        #expect(count == 2)
        #expect(Subscriptions.liveCount == 0)
    }

    @Test func terminateAllEndsALiveSubscription() async throws {
        let client = makeClient(try fakeAerospace(subscriptionStaysAlive: true))
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
        let client = makeClient("/nonexistent/aerospace")
        for await _ in client.events() {}
        #expect(Subscriptions.liveCount == 0)
    }
}
