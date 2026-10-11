/// A workspace's name as AeroSpace reports it (`"1"`, `"M"`, …).
public struct WorkspaceName: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { rawValue }
}

/// A window as AeroSpace numbers it. Higher ids are newer windows.
public struct WindowId: Hashable, Comparable, Sendable, Decodable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.init(value) }
    public init(from decoder: any Decoder) throws { self.init(try decoder.singleValueContainer().decode(Int.self)) }

    public static func < (lhs: WindowId, rhs: WindowId) -> Bool { lhs.rawValue < rhs.rawValue }
    public var description: String { String(rawValue) }
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
    public var id: WindowId
    public var appBundleId: String?
    public var appName: String
    public var appPid: Int32
    public var workspace: WorkspaceName

    public init(id: WindowId, appBundleId: String?, appName: String, appPid: Int32, workspace: WorkspaceName) {
        self.id = id
        self.appBundleId = appBundleId
        self.appName = appName
        self.appPid = appPid
        self.workspace = workspace
    }

    public var appKey: AppKey { AppKey(bundleId: appBundleId, appName: appName) }
    /// The app as one icon.
    public var app: AppRef { AppRef(key: appKey, bundleId: appBundleId, pid: appPid) }
}

/// A window with its title, as `aerospace list-windows --workspace` reports it for the
/// window menu. Titles are read only when the menu opens, never kept.
public struct TitledWindow: Equatable, Sendable {
    public var window: WindowInfo
    public var title: String

    public init(_ window: WindowInfo, title: String) {
        self.window = window
        self.title = title
    }
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
