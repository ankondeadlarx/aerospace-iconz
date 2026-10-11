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
    public static let subscribeArguments = ["subscribe", "--all"]

    public static func windows(from data: Data) throws -> [WindowInfo] {
        try JSONDecoder().decode([RawWindow].self, from: data).map {
            WindowInfo(
                id: $0.windowId,
                appBundleId: ($0.appBundleId?.isEmpty ?? true) ? nil : $0.appBundleId,
                appName: $0.appName,
                appPid: $0.appPid,
                workspace: $0.workspace
            )
        }
    }

    public static func workspaces(from data: Data) throws -> [WorkspaceInfo] {
        try JSONDecoder().decode([RawWorkspace].self, from: data).map {
            WorkspaceInfo(name: $0.workspace, isFocused: $0.isFocused, isVisible: $0.isVisible)
        }
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

    private struct RawEvent: Decodable {
        var event: String
        enum CodingKeys: String, CodingKey { case event = "_event" }
    }
}
