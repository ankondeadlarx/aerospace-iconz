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

    public init(metrics: PillMetrics, maxIconsPerPill: Int, maxTotalWidth: Double) {
        self.metrics = metrics
        self.maxIconsPerPill = maxIconsPerPill
        self.maxTotalWidth = maxTotalWidth
    }
}

/// A workspace ready to draw: the icons that fit and how many were cut.
public struct Pill: Equatable, Sendable {
    public var name: String
    public var isFocused: Bool
    public var isVisible: Bool
    public var icons: [AppRef]
    public var overflow: Int

    public var overflowLabel: String? { overflow > 0 ? "+\(overflow)" : nil }
}

public struct PillFrame: Equatable, Sendable {
    public var x: Double
    public var width: Double
}

/// Where each pill goes. `measure` returns the width of a label string in the label font,
/// which is the only thing that needs AppKit.
public struct PillLayout: Equatable, Sendable {
    public private(set) var pills: [Pill] = []
    public private(set) var frames: [PillFrame] = []
    public private(set) var totalWidth: Double = 0

    public init(groups: [WorkspaceGroup], config: LayoutConfig, measure: (String) -> Double) {
        // Lower the icon cap on unfocused pills one step at a time until everything fits.
        for cap in stride(from: config.maxIconsPerPill, through: 1, by: -1) {
            self = PillLayout(groups: groups, focusedCap: config.maxIconsPerPill, cap: cap,
                              metrics: config.metrics, measure: measure)
            if totalWidth <= config.maxTotalWidth { return }
        }
    }

    private init(groups: [WorkspaceGroup], focusedCap: Int, cap: Int, metrics m: PillMetrics, measure: (String) -> Double) {
        var x = 0.0
        for group in groups {
            let limit = group.isFocused ? focusedCap : cap
            let icons = Array(group.apps.prefix(limit))
            let pill = Pill(name: group.name, isFocused: group.isFocused, isVisible: group.isVisible,
                            icons: icons, overflow: group.apps.count - icons.count)

            var width = m.horizontalPadding * 2 + measure(pill.name)
            if !icons.isEmpty {
                width += m.labelIconGap + Double(icons.count) * m.iconSize + Double(icons.count - 1) * m.iconGap
            }
            if let overflowLabel = pill.overflowLabel {
                width += m.iconGap + measure(overflowLabel)
            }

            if !pills.isEmpty { x += m.pillSpacing }
            pills.append(pill)
            frames.append(PillFrame(x: x, width: width))
            x += width
        }
        totalWidth = x
    }

    /// The workspace a click at `x` targets. Gaps are split down the middle; clicks past
    /// either end go to the edge pill.
    public func workspace(atX x: Double) -> String? {
        for (index, frame) in frames.enumerated() {
            let next = index + 1 < frames.count ? frames[index + 1].x : .infinity
            let boundary = (frame.x + frame.width + next) / 2
            if x < boundary { return pills[index].name }
        }
        return pills.last?.name
    }
}
