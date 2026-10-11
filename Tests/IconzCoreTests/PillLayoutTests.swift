import Testing
@testable import IconzCore

private func app(_ name: String) -> AppRef { AppRef(key: AppKey(bundleId: name, appName: name), bundleId: name, pid: 1) }

private func group(_ name: String, apps count: Int, focused: Bool = false) -> WorkspaceGroup {
    WorkspaceGroup(
        workspace: WorkspaceInfo(name: WorkspaceName(name), isFocused: focused, isVisible: focused),
        apps: (0..<count).map { app("\(name)-\($0)") }
    )
}

/// 10 pt per character keeps the arithmetic readable.
private let measure: @Sendable (String) -> Double = { Double($0.count) * 10 }

// padding 5, label "1" = 10, gap to icons 4, icons 16 with 2 between, spacing 6 between pills.
private let metrics = PillMetrics(
    iconSize: 16, iconGap: 2, labelIconGap: 4, horizontalPadding: 5,
    pillHeight: 20, cornerRadius: 5, pillSpacing: 6
)

private func config(maxIcons: Int = 4, maxWidth: Double = 1000) -> LayoutConfig {
    LayoutConfig(metrics: metrics, maxIconsPerPill: maxIcons, maxTotalWidth: maxWidth, placeholderLabel: "–",
                 hiddenModes: ["main"])
}

private func visibleGroup(_ name: String) -> WorkspaceGroup {
    WorkspaceGroup(workspace: WorkspaceInfo(name: WorkspaceName(name), isFocused: false, isVisible: true), apps: [])
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
        #expect(layout.target(atX: 5) == .workspace("1"))
        #expect(layout.target(atX: 30) == .workspace("2"))
    }

    @Test func clickInGapGoesToNearestPill() {
        // Pill 1 spans 0–20, pill 2 spans 26–46; the gap splits at 23.
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.target(atX: 22) == .workspace("1"))
        #expect(layout.target(atX: 24) == .workspace("2"))
    }

    @Test func clickInTheButtonAllowsForTheCenteredImage() {
        // Pills span 0–46, so centered in a 66 pt button they sit at 10–56 and the gap splits at 33.
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.target(atButtonX: 32, buttonWidth: 66) == .workspace("1"))
        #expect(layout.target(atButtonX: 34, buttonWidth: 66) == .workspace("2"))
    }

    @Test func clickOutsideEverythingMapsToEdgePills() {
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 0)], config: config(), measure: measure)
        #expect(layout.target(atX: -3) == .workspace("1"))
        #expect(layout.target(atX: 99) == .workspace("2"))
        #expect(PillLayout(groups: [], config: config(), measure: measure).target(atX: 0) == nil)
    }

    @Test func partsAreLaidOutInsideThePill() {
        // Second pill, so positions are offset by the first pill (20 wide) + spacing 6.
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 3)], config: config(maxIcons: 2), measure: measure)
        let frame = layout.frames[1]
        #expect(frame.x == 26)
        #expect(frame.labelX == 26 + 5)
        // Label "2" is 10 wide, then the label-icon gap of 4; icons are 16 with 2 between.
        #expect(frame.iconXs == [45, 63])
        // One icon gap after the last icon.
        let expectedOverflowX: Double = 63 + 16 + 2
        #expect(frame.overflowX == expectedOverflowX)
    }

    @Test func clickOnAnIconTargetsItsApp() {
        // Pill "2" at 26: icons at 45 and 63 (16 wide, 2 apart), "+1" at 81.
        let layout = PillLayout(groups: [group("1", apps: 0), group("2", apps: 3)], config: config(maxIcons: 2), measure: measure)
        let first = ClickTarget.app(app("2-0").key, on: "2"), second = ClickTarget.app(app("2-1").key, on: "2")
        #expect(layout.target(atX: 50) == first)
        #expect(layout.target(atX: 64) == second)
        // Half the icon gap on each side belongs to the icon.
        #expect(layout.target(atX: 44.5) == first)
        #expect(layout.target(atX: 79.5) == second)
        // Label, the label–icon gap, `+N` and padding switch workspace.
        #expect(layout.target(atX: 28) == .workspace("2"))
        #expect(layout.target(atX: 33) == .workspace("2"))
        #expect(layout.target(atX: 43) == .workspace("2"))
        #expect(layout.target(atX: 85) == .workspace("2"))
        // Between pills, as before.
        #expect(layout.target(atX: 22) == .workspace("1"))
    }

    @Test func clickOnTheBadgeOrPlaceholderHasNoTarget() {
        let badged = PillLayout(state: .workspaces([group("1", apps: 1, focused: true)], mode: "service"),
                                config: config(), measure: measure)
        #expect(badged.target(atX: 40) == nil)
        #expect(PillLayout(state: .unavailable, config: config(), measure: measure).target(atX: 5) == nil)
    }

    @Test func iconClickInTheButtonAllowsForTheCenteredImage() {
        // One pill 0–40 (icon at 19) centered in a 60 pt button: shifted right by 10.
        let layout = PillLayout(groups: [group("1", apps: 1)], config: config(), measure: measure)
        #expect(layout.target(atButtonX: 35, buttonWidth: 60) == .app(app("1-0").key, on: "1"))
        #expect(layout.target(atButtonX: 20, buttonWidth: 60) == .workspace("1"))
    }

    @Test func pillWithoutIconsHasNoIconOrOverflowPositions() {
        let layout = PillLayout(groups: [group("1", apps: 0, focused: true)], config: config(), measure: measure)
        #expect(layout.frames[0].iconXs.isEmpty)
        #expect(layout.frames[0].overflowX == nil)
    }

    @Test func emphasisFollowsFocusThenVisibility() {
        let layout = PillLayout(
            groups: [group("1", apps: 1, focused: true), visibleGroup("2"), group("3", apps: 1)],
            config: config(), measure: measure
        )
        #expect(layout.pills.map(\.emphasis) == [.fill, .outline, .none])
    }

    @Test func unavailableStateIsOneDimmedOutlinedPlaceholderPill() {
        let layout = PillLayout(state: .unavailable, config: config(), measure: measure)
        #expect(layout.pills.map(\.label) == ["–"])
        #expect(layout.pills.map(\.emphasis) == [.outline])
        #expect(layout.isDimmed)
    }

    @Test func placeholderPillIsNotAWorkspace() {
        let layout = PillLayout(state: .unavailable, config: config(), measure: measure)
        #expect(layout.pills[0].workspace == nil)
        #expect(layout.target(atX: 5) == nil)
    }

    @Test func shownModeIsABadgeBeforeTheFirstPill() {
        let layout = PillLayout(state: .workspaces([group("1", apps: 1, focused: true)], mode: "service"),
                                config: config(), measure: measure)
        #expect(layout.pills.map(\.label) == ["service", "1"])
        #expect(layout.pills.map(\.emphasis) == [.badge, .fill])
        // Badge: padding + "service" (70) + padding, then spacing 6 before pill "1".
        #expect(layout.frames.map(\.x) == [0, 86])
    }

    @Test func hiddenOrUnknownModeHasNoBadge() {
        for mode in ["main", nil] as [String?] {
            let layout = PillLayout(state: .workspaces([group("1", apps: 1, focused: true)], mode: mode),
                                    config: config(), measure: measure)
            #expect(layout.pills.map(\.label) == ["1"])
        }
    }

    @Test func badgeIsNotAWorkspace() {
        let layout = PillLayout(state: .workspaces([group("1", apps: 0, focused: true)], mode: "service"),
                                config: config(), measure: measure)
        #expect(layout.pills[0].workspace == nil)
        // Badge spans 0–80, pill "1" 86–106: the badge's side of the gap and past the left
        // end do nothing, the rest still switches.
        #expect(layout.target(atX: -5) == nil)
        #expect(layout.target(atX: 40) == nil)
        #expect(layout.target(atX: 82) == nil)
        #expect(layout.target(atX: 84) == .workspace("1"))
        #expect(layout.target(atX: 90) == .workspace("1"))
    }

    @Test func badgeCountsTowardTheWidthBudgetButOnlyUnfocusedPillsShrink() {
        // 6 pt/char: badge 52 + 6, focused pill 90 + 6; pill "2" is 68 at cap 2 (total 222)
        // and 50 at cap 1 (total 204), so a 210 budget needs cap 1.
        let narrow: @Sendable (String) -> Double = { Double($0.count) * 6 }
        let groups = [group("1", apps: 4, focused: true), group("2", apps: 4)]
        let layout = PillLayout(state: .workspaces(groups, mode: "service"),
                                config: config(maxWidth: 210), measure: narrow)
        #expect(layout.pills.map(\.label) == ["service", "1", "2"])
        #expect(layout.pills.map(\.icons.count) == [0, 4, 1])
        #expect(layout.totalWidth == 204)
    }

    @Test func workspacesStateIsNotDimmed() {
        let layout = PillLayout(state: .workspaces([group("1", apps: 1, focused: true)]), config: config(), measure: measure)
        #expect(layout.pills.map(\.label) == ["1"])
        #expect(layout.pills.map(\.workspace) == ["1"])
        #expect(!layout.isDimmed)
    }
}
