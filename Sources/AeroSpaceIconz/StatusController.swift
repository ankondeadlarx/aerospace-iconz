import AppKit
import IconzCore
import ServiceManagement

/// Owns the status item: renders state, maps clicks to workspaces, shows the menu.
@MainActor
final class StatusController: NSObject {
    private let config: Config
    private let renderer: PillRenderer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var state: BarState = .unavailable
    /// What's currently drawn; used to map clicks to workspaces.
    private var layout: PillLayout
    private var appearanceObservation: NSKeyValueObservation?

    var onSelectWorkspace: ((WorkspaceName) -> Void)?
    var onRefresh: (() -> Void)?

    init(config: Config) {
        self.config = config
        renderer = PillRenderer(config: config, icons: IconCache())
        layout = renderer.layout(for: .unavailable)
        super.init()

        statusItem.autosaveName = config.statusItemAutosaveName
        statusItem.behavior = []
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("AeroSpace workspaces")
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.redraw() }
            }
        }
        render(.unavailable)
    }

    func render(_ newState: BarState) {
        state = newState
        redraw()
    }

    private func redraw() {
        layout = renderer.layout(for: state)
        statusItem.button?.image = renderer.image(for: layout)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
            return
        }
        // The image is centered in the button; convert the click into image coordinates.
        let point = sender.convert(event.locationInWindow, from: nil)
        let imageOriginX = (sender.bounds.width - layout.totalWidth) / 2
        if let workspace = layout.workspace(atX: point.x - imageOriginX) {
            onSelectWorkspace?(workspace)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AeroSpaceIconz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + config.menuVerticalOffset), in: button)
    }

    @objc private func refresh() { onRefresh?() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }
}
