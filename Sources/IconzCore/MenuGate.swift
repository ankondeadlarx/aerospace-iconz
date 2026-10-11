/// Lets one status item menu up at a time, from the click that asks for it until it has
/// closed. The window menu is read first and pops up a run loop pass later, so a click in
/// between must not open a second one.
public struct MenuGate: Sendable {
    public private(set) var isMenuUp = false

    public init() {}

    /// Whether a menu may open now. If so, it counts as up until `menuClosed()`.
    public mutating func requestMenu() -> Bool {
        guard !isMenuUp else { return false }
        isMenuUp = true
        return true
    }

    public mutating func menuClosed() { isMenuUp = false }
}
