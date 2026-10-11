import Foundation
import Testing
@testable import IconzCore

@Suite struct CLIParsingTests {
    @Test func parsesWindows() throws {
        let json = """
        [
          { "app-bundle-id" : "com.google.Chrome", "app-name" : "Google Chrome",
            "app-pid" : 25346, "window-id" : 20728, "workspace" : "1" },
          { "app-bundle-id" : "md.obsidian", "app-name" : "Obsidian",
            "app-pid" : 26907, "window-id" : 20963, "workspace" : "1" }
        ]
        """
        let windows = try CLIParsing.windows(from: Data(json.utf8))
        #expect(windows == [
            WindowInfo(id: 20728, appBundleId: "com.google.Chrome", appName: "Google Chrome", appPid: 25346, workspace: "1"),
            WindowInfo(id: 20963, appBundleId: "md.obsidian", appName: "Obsidian", appPid: 26907, workspace: "1"),
        ])
    }

    @Test func windowWithoutBundleIdStillParses() throws {
        let json = """
        [{ "app-bundle-id" : "", "app-name" : "Thing", "app-pid" : 1, "window-id" : 2, "workspace" : "3" }]
        """
        let windows = try CLIParsing.windows(from: Data(json.utf8))
        #expect(windows.first?.appBundleId == nil)
    }

    @Test func parsesWorkspaces() throws {
        let json = """
        [
          { "monitor-id" : 1, "workspace" : "1", "workspace-is-focused" : false, "workspace-is-visible" : false },
          { "monitor-id" : 2, "workspace" : "3", "workspace-is-focused" : true, "workspace-is-visible" : true }
        ]
        """
        let workspaces = try CLIParsing.workspaces(from: Data(json.utf8))
        #expect(workspaces == [
            WorkspaceInfo(name: "1", isFocused: false, isVisible: false, monitorId: 1),
            WorkspaceInfo(name: "3", isFocused: true, isVisible: true, monitorId: 2),
        ])
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try CLIParsing.windows(from: Data("nope".utf8)) }
    }

    @Test func parsesEventLine() {
        let event = CLIParsing.event(fromLine: #"{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"1"}"#)
        #expect(event == AeroSpaceEvent(name: "focused-workspace-changed"))
    }

    @Test func ignoresGarbageEventLine() {
        #expect(CLIParsing.event(fromLine: "") == nil)
        #expect(CLIParsing.event(fromLine: "not json") == nil)
    }
}
