/// One window as reported by `aerospace list-windows`.
public struct WindowInfo: Equatable, Sendable {
    public var id: Int
    public var appBundleId: String?
    public var appName: String
    public var appPid: Int32
    public var workspace: String

    public init(id: Int, appBundleId: String?, appName: String, appPid: Int32, workspace: String) {
        self.id = id
        self.appBundleId = appBundleId
        self.appName = appName
        self.appPid = appPid
        self.workspace = workspace
    }
}

/// One workspace as reported by `aerospace list-workspaces`.
public struct WorkspaceInfo: Equatable, Sendable {
    public var name: String
    public var isFocused: Bool
    public var isVisible: Bool
    public var monitorId: Int

    public init(name: String, isFocused: Bool, isVisible: Bool, monitorId: Int) {
        self.name = name
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.monitorId = monitorId
    }
}

/// Everything AeroSpace told us in one refresh.
public struct Snapshot: Equatable, Sendable {
    public var workspaces: [WorkspaceInfo]
    public var windows: [WindowInfo]

    public init(workspaces: [WorkspaceInfo], windows: [WindowInfo]) {
        self.workspaces = workspaces
        self.windows = windows
    }
}

/// A line from `aerospace subscribe`. Only the name matters: any event triggers a re-read.
public struct AeroSpaceEvent: Equatable, Sendable {
    public var name: String

    public init(name: String) { self.name = name }
}
