import Foundation

/// Decodes the `aerospace` CLI's JSON output. The argument lists live here too,
/// so the format strings and the decoders can't drift apart.
public enum CLIParsing {
    /// Everything `WindowInfo` needs; plain `--json` omits the bundle id and workspace.
    private static let windowFormat = "%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}"
    public static let listWindowsArguments = ["list-windows", "--all", "--json", "--format", windowFormat]
    public static let listWorkspacesArguments = [
        "list-workspaces", "--all", "--json",
        "--format", "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
    ]
    public static let listFocusedWindowArguments = [
        "list-windows", "--focused", "--json", "--format", "%{window-id}",
    ]
    public static func listTitledWindowsArguments(on workspace: WorkspaceName) -> [String] {
        ["list-windows", "--workspace", workspace.rawValue, "--json", "--format", windowFormat + " %{window-title}"]
    }
    public static let listModesArguments = ["list-modes", "--current", "--json"]
    public static let subscribeArguments = ["subscribe", "--all"]

    public static func windows(from data: Data) throws -> [WindowInfo] {
        try JSONDecoder().decode([RawWindow].self, from: data).map(\.info)
    }

    public static func titledWindows(from data: Data) throws -> [TitledWindow] {
        try JSONDecoder().decode([RawTitledWindow].self, from: data).map { TitledWindow($0.window.info, title: $0.title) }
    }

    public static func workspaces(from data: Data) throws -> [WorkspaceInfo] {
        try JSONDecoder().decode([RawWorkspace].self, from: data).map {
            WorkspaceInfo(name: WorkspaceName($0.workspace), isFocused: $0.isFocused, isVisible: $0.isVisible)
        }
    }

    /// The current binding mode, or `nil` if AeroSpace reported none.
    public static func mode(from data: Data) throws -> String? {
        try JSONDecoder().decode([RawMode].self, from: data).first?.modeId
    }

    /// The focused window's id, or `nil` if no window has focus.
    public static func focusedWindowId(from data: Data) throws -> WindowId? {
        try JSONDecoder().decode([RawWindowId].self, from: data).first?.windowId
    }

    public static func event(fromLine line: String) -> AeroSpaceEvent? {
        guard (try? JSONDecoder().decode(RawEvent.self, from: Data(line.utf8))) != nil else { return nil }
        return AeroSpaceEvent()
    }

    private struct RawWindow: Decodable {
        var windowId: WindowId
        var appBundleId: String?
        var appName: String
        var appPid: Int32
        var workspace: String

        enum CodingKeys: String, CodingKey {
            case windowId = "window-id", appBundleId = "app-bundle-id", appName = "app-name"
            case appPid = "app-pid", workspace
        }

        var info: WindowInfo {
            WindowInfo(
                id: windowId,
                // Apps without a bundle id report it as "".
                appBundleId: (appBundleId?.isEmpty ?? true) ? nil : appBundleId,
                appName: appName,
                appPid: appPid,
                workspace: WorkspaceName(workspace)
            )
        }
    }

    /// A `RawWindow` plus its title, decoded from the same object.
    private struct RawTitledWindow: Decodable {
        var window: RawWindow
        var title: String

        enum CodingKeys: String, CodingKey { case title = "window-title" }

        init(from decoder: any Decoder) throws {
            window = try RawWindow(from: decoder)
            title = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .title)
        }
    }

    private struct RawWorkspace: Decodable {
        var workspace: String
        var isFocused: Bool
        var isVisible: Bool

        enum CodingKeys: String, CodingKey {
            case workspace, isFocused = "workspace-is-focused", isVisible = "workspace-is-visible"
        }
    }

    private struct RawWindowId: Decodable {
        var windowId: WindowId
        enum CodingKeys: String, CodingKey { case windowId = "window-id" }
    }

    private struct RawMode: Decodable {
        var modeId: String
        enum CodingKeys: String, CodingKey { case modeId = "mode-id" }
    }

    private struct RawEvent: Decodable {
        var event: String
        enum CodingKeys: String, CodingKey { case event = "_event" }
    }
}

/// Splits the `subscribe` byte stream into lines. Reads can end mid-line, or mid-character.
public struct LineSplitter: Sendable {
    private var buffer = Data()

    public init() {}

    /// The lines completed by `data`.
    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    /// At end of stream: the last line, if it had no trailing newline.
    public mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer = Data() }
        return [String(decoding: buffer, as: UTF8.self)]
    }
}
