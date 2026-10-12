import Testing
@testable import IconzCore

@Suite struct MenuOriginTests {
    @Test func notchedBarMenuIsFlushUnderTheBarNotTheShorterButton() {
        // Measured on a 14" MacBook Pro: screen top 1117, visible top 1079, status item window
        // 1080–1117 (37 pt), its 22 pt button 7.5 pt up from the window's bottom.
        let origin = MenuOrigin(buttonMinX: 1300, pillLeft: 10, barBottom: 1080, visibleTop: 1079)
        #expect(origin == MenuOrigin(x: 1310, y: 1079))
    }

    @Test func externalDisplayMenuIsFlushUnderItsShorterBar() {
        // A 2560×1440 display above the built-in: 24 pt bar, window 2557–2581, visible top 2556.
        let origin = MenuOrigin(buttonMinX: 2000, pillLeft: 96, barBottom: 2557, visibleTop: 2556)
        #expect(origin == MenuOrigin(x: 2096, y: 2556))
    }

    @Test func autoHiddenBarMenuIsFlushUnderTheRevealedBar() {
        // An auto-hiding bar reserves nothing: the visible frame reaches the screen top.
        let origin = MenuOrigin(buttonMinX: 1300, pillLeft: 0, barBottom: 1080, visibleTop: 1117)
        #expect(origin == MenuOrigin(x: 1300, y: 1080))
    }
}
