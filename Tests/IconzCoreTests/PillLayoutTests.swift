import Testing
@testable import IconzCore

private func app(_ name: String) -> AppRef { AppRef(key: name, bundleId: name, name: name, pid: 1) }

private func group(_ name: String, apps count: Int, focused: Bool = false) -> WorkspaceGroup {
    WorkspaceGroup(name: name, isFocused: focused, isVisible: focused, apps: (0..<count).map { app("\(name)-\($0)") })
}

/// 10 pt per character keeps the arithmetic readable.
private let measure: @Sendable (String) -> Double = { Double($0.count) * 10 }

// padding 5, label "1" = 10, gap to icons 4, icons 16 with 2 between, spacing 6 between pills.
private let metrics = PillMetrics(
    iconSize: 16, iconGap: 2, labelIconGap: 4, horizontalPadding: 5,
    pillHeight: 20, cornerRadius: 5, pillSpacing: 6
)

private func config(maxIcons: Int = 4, maxWidth: Double = 1000) -> LayoutConfig {
    LayoutConfig(metrics: metrics, maxIconsPerPill: maxIcons, maxTotalWidth: maxWidth)
}

@Suite struct PillLayoutTests {
    @Test func emptyPillIsJustTheLabel() {
        let layout = PillLayout(groups: [group("1", apps: 0, focused: true)], config: config(), measure: measure)
        #expect(layout.frames[0].width == 5 + 10 + 5)
    }

    @Test func pillWidthCountsLabelAndIcons() {
        let layout = PillLayout(groups: [group("1", apps: 2)], config: config(), measure: measure)
        let expected: Double = 5 + 10 + 4 + 16 + 2 + 16 + 5
        #expect(layout.frames[0].width == expected)
    }

    @Test func capsIconsAndCountsOverflow() {
        let layout = PillLayout(groups: [group("1", apps: 6)], config: config(), measure: measure)
        #expect(layout.pills[0].icons.count == 4)
        #expect(layout.pills[0].overflow == 2)
        // padding + label + gap + 4 icons with 3 gaps + icon gap + "+2" (20) + padding.
        let expected: Double = 5 + 10 + 4 + 70 + 2 + 20 + 5
        #expect(layout.frames[0].width == expected)
    }

    @Test func pillsAreLaidOutLeftToRightWithSpacing() {
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.frames.map(\.x) == [0, 26])
        #expect(layout.totalWidth == 20 + 6 + 20)
    }

    @Test func shrinksUnfocusedPillsUntilItFits() {
        // Narrower text (6 pt/char) so "+1" is cheaper than the icon it replaces, as in real fonts.
        let narrow: @Sendable (String) -> Double = { Double($0.count) * 6 }
        let groups = [group("1", apps: 4, focused: true), group("2", apps: 4), group("3", apps: 4)]
        let full = PillLayout(groups: groups, config: config(), measure: narrow)
        let budget = full.totalWidth - 1
        let layout = PillLayout(groups: groups, config: config(maxWidth: budget), measure: narrow)
        #expect(layout.pills.map(\.icons.count) == [4, 3, 3])
        #expect(layout.pills.map(\.overflow) == [0, 1, 1])
        #expect(layout.totalWidth <= budget)
    }

    @Test func keepsShrinkingWhenOneStepIsNotEnough() {
        let groups = [group("1", apps: 4, focused: true), group("2", apps: 4), group("3", apps: 4)]
        let layout = PillLayout(groups: groups, config: config(maxWidth: 240), measure: measure)
        #expect(layout.pills.map(\.icons.count) == [4, 1, 1])
        #expect(layout.totalWidth <= 240)
    }

    @Test func neverShrinksBelowOneIcon() {
        let groups = [group("1", apps: 4, focused: true), group("2", apps: 4)]
        let layout = PillLayout(groups: groups, config: config(maxWidth: 10), measure: measure)
        #expect(layout.pills.map(\.icons.count) == [4, 1])
    }

    @Test func clickInsidePillHitsIt() {
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.workspace(atX: 5) == "1")
        #expect(layout.workspace(atX: 30) == "2")
    }

    @Test func clickInGapGoesToNearestPill() {
        // Pill 1 spans 0–20, pill 2 spans 26–46; the gap splits at 23.
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.workspace(atX: 22) == "1")
        #expect(layout.workspace(atX: 24) == "2")
    }

    @Test func clickOutsideEverythingMapsToEdgePills() {
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.workspace(atX: -3) == "1")
        #expect(layout.workspace(atX: 99) == "2")
        #expect(PillLayout(groups: [], config: config(), measure: measure).workspace(atX: 0) == nil)
    }
}
