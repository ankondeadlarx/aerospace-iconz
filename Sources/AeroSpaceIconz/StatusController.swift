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
    private var iconRetry: Task<Void, Never>?
    private var iconRetriesLeft = 0

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
        iconRetriesLeft = config.iconRetryLimit
        redraw()
    }

    private func redraw() {
        layout = renderer.layout(for: state)
        let rendered = renderer.image(for: layout)
        statusItem.button?.image = rendered.image

        // A launching app can have a window before its icon; draw again once it may have one.
        iconRetry?.cancel()
        guard rendered.isMissingIcons, iconRetriesLeft > 0 else { return }
        iconRetriesLeft -= 1
        iconRetry = Task { [weak self, delay = config.iconRetryDelay] in
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { self?.redraw() }
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
            return
        }
        let point = sender.convert(event.locationInWindow, from: nil)
        if let workspace = layout.workspace(atButtonX: point.x, buttonWidth: sender.bounds.width) {
            onSelectWorkspace?(workspace)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        let launchAtLogin = LaunchAtLoginItem(status: SMAppService.mainApp.status)
        let login = menu.addItem(withTitle: launchAtLogin.title, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLogin.state
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AeroSpaceIconz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + config.menuVerticalOffset), in: button)
    }

    @objc private func refresh() { onRefresh?() }

    @objc private func toggleLaunchAtLogin() {
        do {
            switch LaunchAtLoginItem(status: SMAppService.mainApp.status).action {
            case .register: try SMAppService.mainApp.register()
            case .unregister: try SMAppService.mainApp.unregister()
            case .openSystemSettings: SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            // An accessory app isn't active, so the alert would open behind other windows.
            NSApp.activate()
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login"
            alert.runModal()
        }
    }
}
