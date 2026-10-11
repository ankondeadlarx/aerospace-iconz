/// An app shown as one icon. `key` identifies the app (bundle id, or name when there is none);
/// `pid` is used to look up its icon.
public struct AppRef: Hashable, Sendable {
    public var key: String
    public var bundleId: String?
    public var pid: Int32

    public init(key: String, bundleId: String?, pid: Int32) {
        self.key = key
        self.bundleId = bundleId
        self.pid = pid
    }
}

/// A workspace that should be drawn, with its deduped apps in display order.
public struct WorkspaceGroup: Equatable, Sendable {
    public var name: String
    public var isFocused: Bool
    public var isVisible: Bool
    public var apps: [AppRef]

    public init(name: String, isFocused: Bool, isVisible: Bool, apps: [AppRef]) {
        self.name = name
        self.isFocused = isFocused
        self.isVisible = isVisible
        self.apps = apps
    }
}

/// Turns snapshots into workspace groups. Remembers icon order between snapshots so icons
/// don't jump around: apps keep their position while present, newcomers are appended
/// (ordered by their oldest window id, as a proxy for creation order).
public struct WorkspaceReducer {
    private var order: [String: [String]] = [:]

    public init() {}

    public mutating func groups(for snapshot: Snapshot) -> [WorkspaceGroup] {
        let byWorkspace = Dictionary(grouping: snapshot.windows.sorted { $0.id < $1.id }, by: \.workspace)
        var newOrder: [String: [String]] = [:]

        let groups = snapshot.workspaces.compactMap { workspace -> WorkspaceGroup? in
            var apps: [String: AppRef] = [:]
            var arrival: [String] = []
            for window in byWorkspace[workspace.name] ?? [] {
                let key = window.appBundleId ?? window.appName
                if apps[key] == nil {
                    apps[key] = AppRef(key: key, bundleId: window.appBundleId, pid: window.appPid)
                    arrival.append(key)
                }
            }
            guard !apps.isEmpty || workspace.isFocused else { return nil }

            let kept = (order[workspace.name] ?? []).filter { apps[$0] != nil }
            let keys = kept + arrival.filter { !kept.contains($0) }
            newOrder[workspace.name] = keys
            return WorkspaceGroup(
                name: workspace.name,
                isFocused: workspace.isFocused,
                isVisible: workspace.isVisible,
                apps: keys.compactMap { apps[$0] }
            )
        }

        order = newOrder
        return groups
    }
}
