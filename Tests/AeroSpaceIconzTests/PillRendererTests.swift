import AppKit
import IconzCore
import Testing
@testable import AeroSpaceIconz

private let app = AppRef(key: AppKey(bundleId: "a.b", appName: "A"), bundleId: "a.b", pid: 1)

@MainActor private func layout(_ renderer: PillRenderer) -> PillLayout {
    renderer.layout(for: .workspaces([
        WorkspaceGroup(workspace: WorkspaceInfo(name: "1", isFocused: true, isVisible: true), apps: [app]),
    ]))
}

/// Answers icon lookups with `nil` until `ready` is set, and counts them.
@MainActor private final class Lookup {
    var ready = false
    var calls = 0
    func icon(for _: AppRef) -> NSImage? {
        calls += 1
        return ready ? NSImage(size: NSSize(width: 16, height: 16)) : nil
    }
}

@MainActor @Suite struct PillRendererTests {
    @Test func reportsAnIconThatIsNotAvailableYet() {
        let lookup = Lookup()
        let renderer = PillRenderer(config: .standard, icons: IconCache(lookup: lookup.icon(for:)))
        #expect(renderer.image(for: layout(renderer)).isMissingIcons)
    }

    @Test func triesAMissingIconAgainOnTheNextImage() {
        let lookup = Lookup()
        let renderer = PillRenderer(config: .standard, icons: IconCache(lookup: lookup.icon(for:)))
        _ = renderer.image(for: layout(renderer))
        lookup.ready = true
        #expect(!renderer.image(for: layout(renderer)).isMissingIcons)
    }

    @Test func looksUpAFoundIconOnlyOnce() {
        let lookup = Lookup()
        lookup.ready = true
        let renderer = PillRenderer(config: .standard, icons: IconCache(lookup: lookup.icon(for:)))
        _ = renderer.image(for: layout(renderer))
        _ = renderer.image(for: layout(renderer))
        #expect(lookup.calls == 1)
    }
}
