import Foundation

/// One window in a pill's window menu.
public struct WindowMenuRow: Equatable, Sendable {
    public var windowId: WindowId
    /// For the row's icon.
    public var app: AppRef
    /// The title, or the app name when it has none; cut in the middle when too long.
    public var label: String
    public var isFocused: Bool
}

/// What a pill's window menu lists: that workspace's windows, read when the menu opens.
public struct WindowMenu: Equatable, Sendable {
    public var workspace: WorkspaceName
    public var rows: [WindowMenuRow]
    /// Shown as a disabled row in place of windows: why there are none.
    public var notice: String?

    /// The menu's section header.
    public var title: String { "Workspace \(workspace)" }

    public static func unreadable(_ workspace: WorkspaceName) -> WindowMenu {
        WindowMenu(workspace: workspace, rows: [], notice: "Couldn't read windows")
    }

    private init(workspace: WorkspaceName, rows: [WindowMenuRow], notice: String?) {
        self.workspace = workspace
        self.rows = rows
        self.notice = notice
    }

    /// Rows in the pill's icon order, then window id. Apps not on the pill yet (new since its
    /// last read) come last, ordered by their oldest window, as the pill would add them.
    public init(
        workspace: WorkspaceName, windows: [TitledWindow], iconOrder: [AppKey], focusedWindowId: WindowId?,
        maxTitleLength: Int
    ) {
        let byId = windows.sorted { $0.window.id < $1.window.id }
        var rank: [AppKey: Int] = Dictionary(iconOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        var next = iconOrder.count
        for titled in byId where rank[titled.window.appKey] == nil {
            rank[titled.window.appKey] = next
            next += 1
        }
        let ordered = byId.enumerated()
            .sorted { (rank[$0.element.window.appKey]!, $0.offset) < (rank[$1.element.window.appKey]!, $1.offset) }
            .map(\.element)

        let rows = ordered.map { titled in
            let window = titled.window
            let title = titled.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return WindowMenuRow(
                windowId: window.id,
                app: window.app,
                label: Self.middleTruncated(title.isEmpty ? window.appName : title, to: maxTitleLength),
                isFocused: window.id == focusedWindowId
            )
        }
        self.init(workspace: workspace, rows: rows, notice: rows.isEmpty ? "No windows" : nil)
    }

    /// `text` cut to `limit` characters, the middle replaced by "…".
    static func middleTruncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = limit / 2, tail = limit - 1 - head
        return text.prefix(head) + "…" + text.suffix(tail)
    }
}
