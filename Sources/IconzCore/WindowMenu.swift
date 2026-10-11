import Foundation

/// One window in a pill's window menu.
public struct WindowMenuRow: Equatable, Sendable {
    public var windowId: Int
    /// For the row's icon.
    public var app: AppRef
    /// The title, or the app name when it has none; cut in the middle when too long.
    public var label: String
    public var isFocused: Bool
}

/// What a pill's window menu lists: that workspace's windows, read when the menu opens.
public struct WindowMenu: Equatable, Sendable {
    public var workspace: WorkspaceName
    /// `nil` when the windows couldn't be read; empty when the workspace has none.
    public var rows: [WindowMenuRow]?

    public static func unreadable(_ workspace: WorkspaceName) -> WindowMenu {
        WindowMenu(workspace: workspace, rows: nil)
    }

    private init(workspace: WorkspaceName, rows: [WindowMenuRow]?) {
        self.workspace = workspace
        self.rows = rows
    }

    /// Rows in the pill's icon order, then window id. Apps not on the pill yet (new since its
    /// last read) come last, ordered by their oldest window, as the pill would add them.
    public init(
        workspace: WorkspaceName, windows: [TitledWindow], iconOrder: [AppKey], focusedWindowId: Int?,
        maxTitleLength: Int
    ) {
        let byId = windows.sorted { $0.id < $1.id }
        var rank: [AppKey: Int] = Dictionary(iconOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        var next = iconOrder.count
        for window in byId where rank[window.appKey] == nil {
            rank[window.appKey] = next
            next += 1
        }
        let ordered = byId.enumerated()
            .sorted { (rank[$0.element.appKey]!, $0.offset) < (rank[$1.element.appKey]!, $1.offset) }
            .map(\.element)

        self.init(workspace: workspace, rows: ordered.map { window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return WindowMenuRow(
                windowId: window.id,
                app: AppRef(key: window.appKey, bundleId: window.appBundleId, pid: window.appPid),
                label: Self.middleTruncated(title.isEmpty ? window.appName : title, to: maxTitleLength),
                isFocused: window.id == focusedWindowId
            )
        })
    }

    /// `text` cut to `limit` characters, the middle replaced by "…".
    static func middleTruncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = limit / 2, tail = limit - 1 - head
        return text.prefix(head) + "…" + text.suffix(tail)
    }
}
