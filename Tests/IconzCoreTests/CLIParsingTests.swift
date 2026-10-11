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

    @Test func parsesTitledWindows() throws {
        let json = """
        [{ "app-bundle-id" : "com.mitchellh.ghostty", "app-name" : "Ghostty", "app-pid" : 25368,
           "window-id" : 24106, "window-title" : "claude rc", "workspace" : "1" },
         { "app-bundle-id" : "", "app-name" : "Thing", "app-pid" : 1, "window-id" : 2, "window-title" : "",
           "workspace" : "1" }]
        """
        let windows = try CLIParsing.titledWindows(from: Data(json.utf8))
        #expect(windows == [
            TitledWindow(WindowInfo(id: 24106, appBundleId: "com.mitchellh.ghostty", appName: "Ghostty", appPid: 25368,
                                    workspace: "1"), title: "claude rc"),
            TitledWindow(WindowInfo(id: 2, appBundleId: nil, appName: "Thing", appPid: 1, workspace: "1"), title: ""),
        ])
    }

    @Test func titledWindowsAreListedForOneWorkspace() {
        #expect(CLIParsing.listTitledWindowsArguments(on: "M") == [
            "list-windows", "--workspace", "M", "--json",
            "--format", "%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace} %{window-title}",
        ])
    }

    @Test func parsesWorkspaces() throws {
        let json = """
        [
          { "workspace" : "1", "workspace-is-focused" : false, "workspace-is-visible" : false },
          { "workspace" : "3", "workspace-is-focused" : true, "workspace-is-visible" : true }
        ]
        """
        let workspaces = try CLIParsing.workspaces(from: Data(json.utf8))
        #expect(workspaces == [
            WorkspaceInfo(name: "1", isFocused: false, isVisible: false),
            WorkspaceInfo(name: "3", isFocused: true, isVisible: true),
        ])
    }

    @Test func parsesCurrentMode() throws {
        let json = #"[{ "mode-id" : "service" }]"#
        #expect(try CLIParsing.mode(from: Data(json.utf8)) == "service")
    }

    @Test func noCurrentModeIsNil() throws {
        #expect(try CLIParsing.mode(from: Data("[]".utf8)) == nil)
    }

    @Test func parsesFocusedWindowId() throws {
        #expect(try CLIParsing.focusedWindowId(from: Data(#"[{ "window-id" : 22010 }]"#.utf8)) == 22010)
    }

    @Test func noFocusedWindowIsNil() throws {
        #expect(try CLIParsing.focusedWindowId(from: Data("[]".utf8)) == nil)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try CLIParsing.windows(from: Data("nope".utf8)) }
    }

    @Test func parsesEventLine() {
        let event = CLIParsing.event(fromLine: #"{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"1"}"#)
        #expect(event != nil)
    }

    @Test func ignoresGarbageEventLine() {
        #expect(CLIParsing.event(fromLine: "") == nil)
        #expect(CLIParsing.event(fromLine: "not json") == nil)
    }

    @Test func lineSplitterJoinsALineSplitAcrossReads() {
        var lines = LineSplitter()
        #expect(lines.append(Data(#"{"a":"#.utf8)) == [])
        #expect(lines.append(Data("1}\n{\"b\"".utf8)) == [#"{"a":1}"#])
        #expect(lines.append(Data(":2}\n".utf8)) == [#"{"b":2}"#])
    }

    @Test func lineSplitterKeepsAMultibyteCharacterSplitAcrossReads() {
        var lines = LineSplitter()
        let bytes = Array("é\n".utf8)
        #expect(lines.append(Data(bytes[..<1])) == [])
        #expect(lines.append(Data(bytes[1...])) == ["é"])
    }

    @Test func lineSplitterFlushesAnUnterminatedLastLine() {
        var lines = LineSplitter()
        #expect(lines.append(Data("x\ny".utf8)) == ["x"])
        #expect(lines.finish() == ["y"])
        #expect(lines.finish() == [])
    }
}
