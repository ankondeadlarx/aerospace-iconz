/// Sizes in points. See `Config` for the values in use.
public struct PillMetrics: Equatable, Sendable {
    public var iconSize: Double
    public var iconGap: Double
    public var labelIconGap: Double
    public var horizontalPadding: Double
    public var pillHeight: Double
    public var cornerRadius: Double
    public var pillSpacing: Double

    public init(
        iconSize: Double, iconGap: Double, labelIconGap: Double, horizontalPadding: Double,
        pillHeight: Double, cornerRadius: Double, pillSpacing: Double
    ) {
        self.iconSize = iconSize
        self.iconGap = iconGap
        self.labelIconGap = labelIconGap
        self.horizontalPadding = horizontalPadding
        self.pillHeight = pillHeight
        self.cornerRadius = cornerRadius
        self.pillSpacing = pillSpacing
    }
}

public struct LayoutConfig: Equatable, Sendable {
    public var metrics: PillMetrics
    public var maxIconsPerPill: Int
    public var maxTotalWidth: Double
    /// Label of the single pill shown while AeroSpace can't be reached.
    public var placeholderLabel: String
    /// Binding modes that get no badge.
    public var hiddenModes: Set<String>

    public init(
        metrics: PillMetrics, maxIconsPerPill: Int, maxTotalWidth: Double, placeholderLabel: String,
        hiddenModes: Set<String>
    ) {
        self.metrics = metrics
        self.maxIconsPerPill = maxIconsPerPill
        self.maxTotalWidth = maxTotalWidth
        self.placeholderLabel = placeholderLabel
        self.hiddenModes = hiddenModes
    }
}

/// How a pill's background is drawn.
public enum PillEmphasis: Equatable, Sendable {
    /// The focused workspace.
    case fill
    /// Visible on another monitor, or the placeholder.
    case outline
    case none
    /// The binding-mode badge.
    case badge
}

/// A pill ready to draw: the icons that fit and how many were cut.
public struct Pill: Equatable, Sendable {
    public var label: String
    /// The workspace a click switches to; `nil` for the placeholder and the mode badge.
    public var workspace: WorkspaceName?
    public var emphasis: PillEmphasis
    public var icons: [AppRef]
    public var overflow: Int

    public var overflowLabel: String? { overflow > 0 ? "+\(overflow)" : nil }
}

/// What a click on the bar acts on.
public enum ClickTarget: Equatable, Sendable {
    case workspace(WorkspaceName)
    /// An app's icon in that workspace's pill.
    case app(AppKey, on: WorkspaceName)
}

/// Where a pill and each of its parts go, in points from the left of the image.
/// The renderer draws at exactly these positions, so drawing and click hit-testing can't drift.
public struct PillFrame: Equatable, Sendable {
    public var x: Double
    public var width: Double
    public var labelX: Double
    public var iconXs: [Double]
    public var overflowX: Double?
}

/// Where each pill goes. `measure` returns the width of a label string in the label font,
/// which is the only thing that needs AppKit.
public struct PillLayout: Equatable, Sendable {
    public private(set) var pills: [Pill] = []
    public private(set) var frames: [PillFrame] = []
    public private(set) var totalWidth: Double = 0
    /// Drawn at reduced opacity: AeroSpace can't be reached.
    public private(set) var isDimmed = false
    private var metrics: PillMetrics

    public init(state: BarState, config: LayoutConfig, measure: (String) -> Double) {
        switch state {
        case .workspaces(let groups, let mode):
            self.init(groups: groups, mode: mode, config: config, measure: measure)
        case .unavailable:
            let placeholder = PillSource(
                label: config.placeholderLabel, workspace: nil, isFocused: false, emphasis: .outline, apps: []
            )
            self.init(sources: [placeholder], config: config, measure: measure)
            isDimmed = true
        }
    }

    public init(groups: [WorkspaceGroup], mode: String? = nil, config: LayoutConfig, measure: (String) -> Double) {
        var sources: [PillSource] = []
        if let mode, !config.hiddenModes.contains(mode) {
            sources.append(PillSource(label: mode, workspace: nil, isFocused: false, emphasis: .badge, apps: []))
        }
        sources += groups.map { group in
            let workspace = group.workspace
            return PillSource(
                label: workspace.name.rawValue,
                workspace: workspace.name,
                isFocused: workspace.isFocused,
                emphasis: workspace.isFocused ? .fill : workspace.isVisible ? .outline : .none,
                apps: group.apps
            )
        }
        self.init(sources: sources, config: config, measure: measure)
    }

    private init(sources: [PillSource], config: LayoutConfig, measure: (String) -> Double) {
        // Lower the icon cap on unfocused pills one step at a time until everything fits.
        var cap = config.maxIconsPerPill + 1
        repeat {
            cap -= 1
            self = PillLayout(sources: sources, focusedCap: config.maxIconsPerPill, cap: cap,
                              metrics: config.metrics, measure: measure)
        } while totalWidth > config.maxTotalWidth && cap > 1
    }

    private init(sources: [PillSource], focusedCap: Int, cap: Int, metrics: PillMetrics, measure: (String) -> Double) {
        self.metrics = metrics
        var x = 0.0
        for source in sources {
            let limit = source.isFocused ? focusedCap : cap
            let icons = Array(source.apps.prefix(limit))
            let pill = Pill(label: source.label, workspace: source.workspace, emphasis: source.emphasis,
                            icons: icons, overflow: source.apps.count - icons.count)

            if !pills.isEmpty { x += metrics.pillSpacing }
            let labelX = x + metrics.horizontalPadding
            var cursor = labelX + measure(pill.label)
            var iconXs: [Double] = []
            for index in icons.indices {
                cursor += index == 0 ? metrics.labelIconGap : metrics.iconGap
                iconXs.append(cursor)
                cursor += metrics.iconSize
            }
            var overflowX: Double?
            if let overflowLabel = pill.overflowLabel {
                cursor += metrics.iconGap
                overflowX = cursor
                cursor += measure(overflowLabel)
            }
            let width = cursor + metrics.horizontalPadding - x

            pills.append(pill)
            frames.append(PillFrame(x: x, width: width, labelX: labelX, iconXs: iconXs, overflowX: overflowX))
            x += width
        }
        totalWidth = x
    }

    /// What a click at `x` acts on: an icon (with half the icon gap on each side), else its
    /// pill's workspace. Gaps between pills are split down the middle; clicks past either
    /// end go to the edge pill. The badge and the placeholder have no target.
    public func target(atX x: Double) -> ClickTarget? {
        guard let index = pillIndex(atX: x), let workspace = pills[index].workspace else { return nil }
        let reach = metrics.iconGap / 2
        for (icon, iconX) in zip(pills[index].icons, frames[index].iconXs)
        where x >= iconX - reach && x < iconX + metrics.iconSize + reach {
            return .app(icon.key, on: workspace)
        }
        return .workspace(workspace)
    }

    private func pillIndex(atX x: Double) -> Int? {
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].x : .infinity
            if x < (frame.x + frame.width + next) / 2 { return index }
        }
        return pills.indices.last
    }

    /// `target(atX:)` for a click in the status item's button. The button can be wider than
    /// the image, which it draws centered.
    public func target(atButtonX x: Double, buttonWidth: Double) -> ClickTarget? {
        target(atX: x - (buttonWidth - totalWidth) / 2)
    }
}

/// What a pill is built from: a workspace group, or the placeholder.
private struct PillSource {
    var label: String
    var workspace: WorkspaceName?
    /// Keeps the full icon cap when the bar is too wide.
    var isFocused: Bool
    var emphasis: PillEmphasis
    var apps: [AppRef]
}
