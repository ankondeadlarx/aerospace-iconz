import Foundation

/// Decodes the `aerospace` CLI's JSON output. The argument lists live here too,
/// so the format strings and the decoders can't drift apart.
public enum CLIParsing {
    public static let listWindowsArguments = [
        "list-windows", "--all", "--json",
        "--format", "%{window-id} %{app-bundle-id} %{app-name} %{app-pid} %{workspace}",
    ]
    public static let listWorkspacesArguments = [
        "list-workspaces", "--all", "--json",
        "--format", "%{workspace} %{workspace-is-focused} %{workspace-is-visible}",
    ]
    public static let listModesArguments = ["list-modes", "--current", "--json"]
    public static let subscribeArguments = ["subscribe", "--all"]

    public static func windows(from data: Data) throws -> [WindowInfo] {
        try JSONDecoder().decode([RawWindow].self, from: data).map {
            WindowInfo(
                id: $0.windowId,
                appBundleId: ($0.appBundleId?.isEmpty ?? true) ? nil : $0.appBundleId,
                appName: $0.appName,
                appPid: $0.appPid,
                workspace: WorkspaceName($0.workspace)
            )
        }
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

    public static func event(fromLine line: String) -> AeroSpaceEvent? {
        guard (try? JSONDecoder().decode(RawEvent.self, from: Data(line.utf8))) != nil else { return nil }
        return AeroSpaceEvent()
    }

    private struct RawWindow: Decodable {
        var windowId: Int
        var appBundleId: String?
        var appName: String
        var appPid: Int32
        var workspace: String

        enum CodingKeys: String, CodingKey {
            case windowId = "window-id", appBundleId = "app-bundle-id", appName = "app-name"
            case appPid = "app-pid", workspace
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
