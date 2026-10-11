import Testing
@testable import IconzCore

private func window(_ id: Int, _ app: String, _ title: String = "") -> TitledWindow {
    TitledWindow(WindowInfo(id: id, appBundleId: app, appName: app.uppercased(), appPid: 1, workspace: "1"), title: title)
}

private func key(_ app: String) -> AppKey { AppKey(bundleId: app, appName: app.uppercased()) }

private func menu(
    _ windows: [TitledWindow], order: [String] = [], focused: Int? = nil, maxTitleLength: Int = 60
) -> WindowMenu {
    WindowMenu(workspace: "1", windows: windows, iconOrder: order.map(key), focusedWindowId: focused,
               maxTitleLength: maxTitleLength)
}

@Suite struct WindowMenuTests {
    @Test func rowsFollowTheIconOrderThenWindowId() {
        let rows = menu([window(30, "a"), window(20, "b"), window(10, "a")], order: ["b", "a"]).rows
        #expect(rows.map(\.windowId) == [20, 10, 30])
    }

    @Test func appsNotOnThePillComeLastByTheirOldestWindow() {
        let windows = [window(9, "late"), window(50, "new"), window(3, "new"), window(20, "a")]
        let rows = menu(windows, order: ["a"]).rows
        #expect(rows.map(\.windowId) == [20, 3, 50, 9])
    }

    @Test func labelIsTheTitleOrElseTheAppName() {
        let rows = menu([window(1, "a", "Inbox"), window(2, "b", ""), window(3, "c", "  ")], order: ["a", "b", "c"]).rows
        #expect(rows.map(\.label) == ["Inbox", "B", "C"])
    }

    @Test func longTitlesAreCutInTheMiddle() {
        let rows = menu([window(1, "a", "abcdefghij")], order: ["a"], maxTitleLength: 7).rows
        #expect(rows.first?.label == "abc…hij")
        let fits = menu([window(1, "a", "abcdefg")], order: ["a"], maxTitleLength: 7).rows
        #expect(fits.first?.label == "abcdefg")
    }

    @Test func truncationCountsCharactersNotBytes() {
        let rows = menu([window(1, "a", "🚀🚀🚀éééé")], order: ["a"], maxTitleLength: 5).rows
        #expect(rows.first?.label == "🚀🚀…éé")
    }

    @Test func onlyTheFocusedWindowIsChecked() {
        let rows = menu([window(1, "a"), window(2, "a")], order: ["a"], focused: 2).rows
        #expect(rows.map(\.isFocused) == [false, true])
        let elsewhere = menu([window(1, "a")], order: ["a"], focused: 99).rows
        #expect(elsewhere.map(\.isFocused) == [false])
    }

    @Test func rowCarriesItsAppForTheIcon() {
        let thing = WindowInfo(id: 1, appBundleId: nil, appName: "Thing", appPid: 7, workspace: "1")
        let rows = menu([TitledWindow(thing, title: "x")]).rows
        #expect(rows.first?.app == AppRef(key: AppKey(bundleId: nil, appName: "Thing"), bundleId: nil, pid: 7))
    }

    @Test func titleNamesTheWorkspace() {
        #expect(menu([]).title == "Workspace 1")
    }

    @Test func emptyWorkspaceSaysSo() {
        let empty = menu([])
        #expect(empty.rows.isEmpty)
        #expect(empty.notice == "No windows")
        #expect(menu([window(1, "a")]).notice == nil)
    }

    @Test func unreadableMenuSaysSo() {
        let unreadable = WindowMenu.unreadable("3")
        #expect(unreadable.title == "Workspace 3")
        #expect(unreadable.rows.isEmpty)
        #expect(unreadable.notice == "Couldn't read windows")
    }
}
