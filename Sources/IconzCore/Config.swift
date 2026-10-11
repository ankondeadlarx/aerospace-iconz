/// Every tunable in one place. Edit and rebuild (`make install`).
public struct Config: Sendable {
    public var layout: LayoutConfig
    public var timing: Timing

    public var labelFontSize: Double
    /// `NSFont.Weight` raw value (0.23 = medium).
    public var labelFontWeight: Double
    /// Opacity of the `+N` overflow label, relative to the label color.
    public var overflowLabelAlpha: Double
    /// Fill of the focused pill, as a fraction of the menu bar's label color.
    public var focusedFillAlpha: Double
    /// Outline of a pill visible on another monitor.
    public var visibleStrokeWidth: Double
    public var visibleStrokeAlpha: Double
    /// Opacity of the placeholder shown when AeroSpace can't be reached.
    public var unavailableAlpha: Double

    /// While an app's icon isn't available yet (it's still launching), redraw this often,
    /// up to `iconRetryLimit` times per state.
    public var iconRetryDelay: Duration
    public var iconRetryLimit: Int

    /// Gap between the status item and the top of its right-click menu.
    public var menuVerticalOffset: Double

    public var statusItemAutosaveName: String
    /// GUI apps don't inherit the shell PATH, so look in the usual Homebrew locations.
    public var aerospaceExecutableCandidates: [String]
    /// A CLI call taking longer is killed and counts as AeroSpace being unreachable.
    /// Normal calls take ~15 ms.
    public var cliTimeout: Duration

    public static let standard = Config(
        layout: LayoutConfig(
            metrics: PillMetrics(
                iconSize: 20, iconGap: 2, labelIconGap: 4, horizontalPadding: 6,
                pillHeight: 24, cornerRadius: 6, pillSpacing: 6
            ),
            maxIconsPerPill: 4,
            maxTotalWidth: 500,
            placeholderLabel: "–",
            hiddenModes: ["main"]
        ),
        timing: Timing(
            burstDelays: [.milliseconds(100), .milliseconds(500)],
            pollInterval: .seconds(3),
            reconnectBackoff: [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]
        ),
        labelFontSize: 12,
        labelFontWeight: 0.23,
        overflowLabelAlpha: 0.55,
        focusedFillAlpha: 0.2,
        visibleStrokeWidth: 1,
        visibleStrokeAlpha: 0.35,
        unavailableAlpha: 0.4,
        iconRetryDelay: .seconds(1),
        iconRetryLimit: 5,
        menuVerticalOffset: 4,
        statusItemAutosaveName: "AeroSpaceIconz",
        aerospaceExecutableCandidates: ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"],
        cliTimeout: .seconds(2)
    )
}

public struct Timing: Sendable {
    /// Extra re-reads after each event, measured from the event. Covers events that fire
    /// before AeroSpace has finished applying the change.
    public var burstDelays: [Duration]
    /// Safety-net re-read for changes AeroSpace has no event for (window closed, moved by mouse).
    public var pollInterval: Duration
    /// Wait before restarting `aerospace subscribe`, by consecutive failed attempt.
    public var reconnectBackoff: [Duration]

    public func reconnectDelay(attempt: Int) -> Duration {
        reconnectBackoff[min(attempt, reconnectBackoff.count - 1)]
    }
}
