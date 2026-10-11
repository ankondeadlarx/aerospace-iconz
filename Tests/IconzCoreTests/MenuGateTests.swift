import Testing
@testable import IconzCore

// `#expect` can't call a mutating method, so each answer is bound first.
@Suite struct MenuGateTests {
    @Test func firstRequestOpens() {
        var gate = MenuGate()
        let opened = gate.requestMenu()
        #expect(opened)
        #expect(gate.isMenuUp)
    }

    @Test func requestsWhileAMenuIsUpAreRefused() {
        var gate = MenuGate()
        _ = gate.requestMenu()
        let second = gate.requestMenu(), third = gate.requestMenu()
        #expect(!second)
        #expect(!third)
    }

    @Test func aClosedMenuLetsTheNextOneOpen() {
        var gate = MenuGate()
        _ = gate.requestMenu()
        gate.menuClosed()
        #expect(!gate.isMenuUp)
        let reopened = gate.requestMenu()
        #expect(reopened)
    }
}
