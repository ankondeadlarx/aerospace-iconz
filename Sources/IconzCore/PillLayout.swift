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

    public init(metrics: PillMetrics, maxIconsPerPill: Int, maxTotalWidth: Double, placeholderLabel: String) {
        self.metrics = metrics
        self.maxIconsPerPill = maxIconsPerPill
        self.maxTotalWidth = maxTotalWidth
        self.placeholderLabel = placeholderLabel
    }
}

/// How a pill's background is drawn.
public enum PillEmphasis: Equatable, Sendable {
    /// The focused workspace.
    case fill
    /// Visible on another monitor, or the placeholder.
    case outline
    case none
}

/// A pill ready to draw: the icons that fit and how many were cut.
public struct Pill: Equatable, Sendable {
    public var label: String
    /// The workspace a click switches to; `nil` for the placeholder.
    public var workspace: WorkspaceName?
    public var emphasis: PillEmphasis
    public var icons: [AppRef]
    public var overflow: Int

    public var overflowLabel: String? { overflow > 0 ? "+\(overflow)" : nil }
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

    public init(state: BarState, config: LayoutConfig, measure: (String) -> Double) {
        switch state {
        case .workspaces(let groups):
            self.init(groups: groups, config: config, measure: measure)
        case .unavailable:
            let placeholder = PillSource(label: config.placeholderLabel, workspace: nil, emphasis: .outline, apps: [])
            self.init(sources: [placeholder], config: config, measure: measure)
            isDimmed = true
        }
    }

    public init(groups: [WorkspaceGroup], config: LayoutConfig, measure: (String) -> Double) {
        let sources = groups.map { group in
            let workspace = group.workspace
            return PillSource(
                label: workspace.name.rawValue,
                workspace: workspace.name,
                emphasis: workspace.isFocused ? .fill : workspace.isVisible ? .outline : .none,
                apps: group.apps
            )
        }
        self.init(sources: sources, config: config, measure: measure)
    }

    private init(sources: [PillSource], config: LayoutConfig, measure: (String) -> Double) {
        // Lower the icon cap on unfocused pills one step at a time until everything fits.
        for cap in stride(from: config.maxIconsPerPill, through: 1, by: -1) {
            self = PillLayout(sources: sources, focusedCap: config.maxIconsPerPill, cap: cap,
                              metrics: config.metrics, measure: measure)
            if totalWidth <= config.maxTotalWidth { return }
        }
    }

    private init(sources: [PillSource], focusedCap: Int, cap: Int, metrics m: PillMetrics, measure: (String) -> Double) {
        var x = 0.0
        for source in sources {
            let limit = source.emphasis == .fill ? focusedCap : cap
            let icons = Array(source.apps.prefix(limit))
            let pill = Pill(label: source.label, workspace: source.workspace, emphasis: source.emphasis,
                            icons: icons, overflow: source.apps.count - icons.count)

            if !pills.isEmpty { x += m.pillSpacing }
            let labelX = x + m.horizontalPadding
            var cursor = labelX + measure(pill.label)
            var iconXs: [Double] = []
            for index in icons.indices {
                cursor += index == 0 ? m.labelIconGap : m.iconGap
                iconXs.append(cursor)
                cursor += m.iconSize
            }
            var overflowX: Double?
            if let overflowLabel = pill.overflowLabel {
                cursor += m.iconGap
                overflowX = cursor
                cursor += measure(overflowLabel)
            }
            let width = cursor + m.horizontalPadding - x

            pills.append(pill)
            frames.append(PillFrame(x: x, width: width, labelX: labelX, iconXs: iconXs, overflowX: overflowX))
            x += width
        }
        totalWidth = x
    }

    /// The workspace a click at `x` targets. Gaps are split down the middle; clicks past
    /// either end go to the edge pill.
    public func workspace(atX x: Double) -> WorkspaceName? {
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].x : .infinity
            let boundary = (frame.x + frame.width + next) / 2
            if x < boundary { return pills[index].workspace }
        }
        return pills.last?.workspace
    }
}

/// What a pill is built from: a workspace group, or the placeholder.
private struct PillSource {
    var label: String
    var workspace: WorkspaceName?
    var emphasis: PillEmphasis
    var apps: [AppRef]
}
