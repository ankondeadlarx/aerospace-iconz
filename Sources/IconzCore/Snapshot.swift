/// A workspace's name as AeroSpace reports it (`"1"`, `"M"`, …).
public struct WorkspaceName: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { rawValue }
}

/// Identifies an app for deduping and icon caching: its bundle id, or its name when it has none.
public struct AppKey: Hashable, Sendable {
    public let rawValue: String

    public init(bundleId: String?, appName: String) {
        rawValue = bundleId ?? appName
    }
}

/// One window as reported by `aerospace list-windows`.
public struct WindowInfo: Equatable, Sendable {
    public var id: Int
    public var appBundleId: String?
    public var appName: String
    public var appPid: Int32
    public var workspace: WorkspaceName

    public init(id: Int, appBundleId: String?, appName: String, appPid: Int32, workspace: WorkspaceName) {
        self.id = id
        self.appBundleId = appBundleId
        self.appName = appName
        self.appPid = appPid
        self.workspace = workspace
    }

    public var appKey: AppKey { AppKey(bundleId: appBundleId, appName: appName) }
}

/// One workspace as reported by `aerospace list-workspaces`.
public struct WorkspaceInfo: Equatable, Sendable {
    public var name: WorkspaceName
    public var isFocused: Bool
    public var isVisible: Bool

    public init(name: WorkspaceName, isFocused: Bool, isVisible: Bool) {
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
