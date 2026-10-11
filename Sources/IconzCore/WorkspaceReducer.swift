/// An app shown as one icon. `pid` is used to look up its icon.
public struct AppRef: Hashable, Sendable {
    public var key: AppKey
    public var bundleId: String?
    public var pid: Int32

    public init(key: AppKey, bundleId: String?, pid: Int32) {
        self.key = key
        self.bundleId = bundleId
        self.pid = pid
    }
}

/// A workspace that should be drawn, with its deduped apps in display order.
public struct WorkspaceGroup: Equatable, Sendable {
    public var workspace: WorkspaceInfo
    public var apps: [AppRef]

    public init(workspace: WorkspaceInfo, apps: [AppRef]) {
        self.workspace = workspace
        self.apps = apps
    }
}

/// Turns snapshots into workspace groups. Remembers icon order between snapshots so icons
/// don't jump around: apps keep their position while present, newcomers are appended
/// (ordered by their oldest window id, as a proxy for creation order).
public struct WorkspaceReducer {
    private var order: [WorkspaceName: [AppKey]] = [:]

    public init() {}

    public mutating func groups(for snapshot: Snapshot) -> [WorkspaceGroup] {
        let byWorkspace = Dictionary(grouping: snapshot.windows.sorted { $0.id < $1.id }, by: \.workspace)
        var newOrder: [WorkspaceName: [AppKey]] = [:]

        let groups = snapshot.workspaces.compactMap { workspace -> WorkspaceGroup? in
            var apps: [AppKey: AppRef] = [:]
            var arrival: [AppKey] = []
            for window in byWorkspace[workspace.name] ?? [] {
                let key = window.appKey
                if apps[key] == nil {
                    apps[key] = window.app
                    arrival.append(key)
                }
            }
            guard !apps.isEmpty || workspace.isFocused else { return nil }

            let kept = (order[workspace.name] ?? []).filter { apps[$0] != nil }
            let keys = kept + arrival.filter { !kept.contains($0) }
            newOrder[workspace.name] = keys
            return WorkspaceGroup(workspace: workspace, apps: keys.compactMap { apps[$0] })
        }

        order = newOrder
        return groups
    }
}
