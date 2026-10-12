/// Where the status item's menu opens: its top-left corner, in screen points (y up).
public struct MenuOrigin: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Flush under the menu bar, starting under the clicked pill. The bar's bottom comes from
    /// the screen, never the button: on notched Macs the 22 pt button sits centered in a 37 pt
    /// bar, and a menu that reaches into the bar opens scrolled, behind a scroll arrow.
    /// - Parameters:
    ///   - buttonMinX: the status item button's left edge on screen.
    ///   - pillLeft: the pill's left edge in the button (`PillLayout.pillLeft`).
    ///   - barBottom: the bottom of the status item's window, which is as tall as the bar.
    ///   - visibleTop: the top of its screen's visible frame. A shown bar reserves a hairline
    ///     more than its window; an auto-hiding one reserves nothing.
    public init(buttonMinX: Double, pillLeft: Double, barBottom: Double, visibleTop: Double) {
        self.init(x: buttonMinX + pillLeft, y: min(barBottom, visibleTop))
    }
}
