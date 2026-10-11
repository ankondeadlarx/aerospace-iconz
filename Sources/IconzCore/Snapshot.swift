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

    public init(name: String, isFocused: Bool, isVisible: Bool) {
        self.name = name
        self.isFocused = isFocused
        self.isVisible = isVisible
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

/// A line from `aerospace subscribe`. Carries nothing: any event triggers a full re-read.
public struct AeroSpaceEvent: Equatable, Sendable {
    public init() {}
}
