import Testing
@testable import IconzCore

private func ws(_ name: String, focused: Bool = false, visible: Bool = false) -> WorkspaceInfo {
    WorkspaceInfo(name: name, isFocused: focused, isVisible: visible || focused, monitorId: 1)
}

private func win(_ id: Int, _ app: String, on workspace: String, pid: Int32? = nil) -> WindowInfo {
    WindowInfo(id: id, appBundleId: "bundle.\(app)", appName: app, appPid: pid ?? Int32(app.hashValue & 0xFFFF), workspace: workspace)
}

private func appNames(_ groups: [WorkspaceGroup]) -> [String: [String]] {
    Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.apps.map(\.name)) })
}

@Suite struct WorkspaceReducerTests {
    @Test func hidesEmptyWorkspacesButKeepsFocusedOne() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1"), ws("2"), ws("3", focused: true)],
            windows: [win(1, "Chrome", on: "1")]
        ))
        #expect(groups.map(\.name) == ["1", "3"])
        #expect(groups[1].apps.isEmpty)
        #expect(groups[1].isFocused)
    }

    @Test func keepsAeroSpaceWorkspaceOrder() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("B"), ws("A")],
            windows: [win(1, "X", on: "A"), win(2, "Y", on: "B")]
        ))
        #expect(groups.map(\.name) == ["B", "A"])
    }

    @Test func showsEachAppOncePerWorkspace() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1")],
            windows: [win(1, "Chrome", on: "1"), win(2, "Chrome", on: "1"), win(3, "Obsidian", on: "1")]
        ))
        #expect(appNames(groups)["1"] == ["Chrome", "Obsidian"])
    }

    @Test func initialOrderFollowsWindowCreationOrder() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1")],
            windows: [win(30, "Chrome", on: "1"), win(10, "Obsidian", on: "1"), win(20, "Preview", on: "1")]
        ))
        #expect(appNames(groups)["1"] == ["Obsidian", "Preview", "Chrome"])
    }

    @Test func existingAppsKeepTheirPositionWhenTheirWindowsChange() {
        var reducer = WorkspaceReducer()
        _ = reducer.groups(for: Snapshot(
            workspaces: [ws("1")],
            windows: [win(1, "A", on: "1"), win(2, "B", on: "1")]
        ))
        // A's original window closed, A opened a newer one; C is brand new.
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1")],
            windows: [win(2, "B", on: "1"), win(5, "C", on: "1"), win(9, "A", on: "1")]
        ))
        #expect(appNames(groups)["1"] == ["A", "B", "C"])
    }

    @Test func appThatLeavesAndReturnsGoesToTheEnd() {
        var reducer = WorkspaceReducer()
        let both = Snapshot(workspaces: [ws("1")], windows: [win(1, "A", on: "1"), win(2, "B", on: "1")])
        _ = reducer.groups(for: both)
        _ = reducer.groups(for: Snapshot(workspaces: [ws("1")], windows: [win(2, "B", on: "1")]))
        let groups = reducer.groups(for: both)
        #expect(appNames(groups)["1"] == ["B", "A"])
    }

    @Test func appMovedToAnotherWorkspaceIsAppendedThere() {
        var reducer = WorkspaceReducer()
        _ = reducer.groups(for: Snapshot(
            workspaces: [ws("1"), ws("2")],
            windows: [win(1, "A", on: "1"), win(2, "B", on: "2"), win(3, "C", on: "2")]
        ))
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1"), ws("2")],
            windows: [win(1, "A", on: "2"), win(2, "B", on: "2"), win(3, "C", on: "2")]
        ))
        #expect(groups.map(\.name) == ["2"])
        #expect(appNames(groups)["2"] == ["B", "C", "A"])
    }

    @Test func appsWithoutBundleIdAreKeyedByName() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1")],
            windows: [
                WindowInfo(id: 1, appBundleId: nil, appName: "Tool", appPid: 7, workspace: "1"),
                WindowInfo(id: 2, appBundleId: nil, appName: "Tool", appPid: 7, workspace: "1"),
            ]
        ))
        #expect(groups[0].apps == [AppRef(key: "Tool", bundleId: nil, name: "Tool", pid: 7)])
    }

    @Test func carriesFocusAndVisibility() {
        var reducer = WorkspaceReducer()
        let groups = reducer.groups(for: Snapshot(
            workspaces: [ws("1", focused: true), ws("2", visible: true), ws("3")],
            windows: [win(1, "A", on: "1"), win(2, "B", on: "2"), win(3, "C", on: "3")]
        ))
        #expect(groups.map(\.isFocused) == [true, false, false])
        #expect(groups.map(\.isVisible) == [true, true, false])
    }
}
