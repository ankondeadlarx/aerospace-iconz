/// Every tunable in one place. Edit and rebuild (`make install`).
public struct Config: Sendable {
    public var layout: LayoutConfig
    public var timing: Timing

    public var labelFontSize: Double
    /// Fill of the focused pill, as a fraction of the menu bar's label color.
    public var focusedFillAlpha: Double
    /// Outline of a pill visible on another monitor.
    public var visibleStrokeWidth: Double
    public var visibleStrokeAlpha: Double
    /// Opacity of the placeholder shown when AeroSpace can't be reached.
    public var unavailableAlpha: Double

    public var statusItemAutosaveName: String
    /// GUI apps don't inherit the shell PATH, so look in the usual Homebrew locations.
    public var aerospaceExecutableCandidates: [String]

    public static let standard = Config(
        layout: LayoutConfig(
            metrics: PillMetrics(
                iconSize: 16, iconGap: 2, labelIconGap: 4, horizontalPadding: 5,
                pillHeight: 20, cornerRadius: 5, pillSpacing: 6
            ),
            maxIconsPerPill: 4,
            maxTotalWidth: 400
        ),
        timing: Timing(
            burstDelays: [.milliseconds(100), .milliseconds(500)],
            pollInterval: .seconds(3),
            reconnectBackoff: [.seconds(1), .seconds(2), .seconds(5), .seconds(10)]
        ),
        labelFontSize: 11,
        focusedFillAlpha: 0.2,
        visibleStrokeWidth: 1,
        visibleStrokeAlpha: 0.35,
        unavailableAlpha: 0.4,
        statusItemAutosaveName: "AeroSpaceIconz",
        aerospaceExecutableCandidates: ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
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
