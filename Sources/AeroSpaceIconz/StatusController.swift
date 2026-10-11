import AppKit
import IconzCore
import ServiceManagement

/// Owns the status item: renders state, maps clicks to workspaces and app icons, shows the menu
/// (with the clicked pill's windows on top).
@MainActor
final class StatusController: NSObject {
    private let config: Config
    private let renderer: PillRenderer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var state: BarState = .unavailable
    /// What's currently drawn; used to map clicks to what they act on.
    private var layout: PillLayout
    private var appearanceObservation: NSKeyValueObservation?
    private var iconRetry: Task<Void, Never>?
    private var iconRetriesLeft = 0

    var onClick: ((ClickTarget) -> Void)?
    var onRefresh: (() -> Void)?
    /// Reads a pill's window menu; `nil` while another one is still being read.
    var readWindowMenu: ((WorkspaceName) async -> WindowMenu?)?
    /// A window menu row was chosen: focus that window, on that workspace.
    var onChooseWindow: ((Int, WorkspaceName) -> Void)?

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
        let x = sender.convert(event.locationInWindow, from: nil).x
        let width = sender.bounds.width
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            if let workspace = layout.workspace(atButtonX: x, buttonWidth: width) {
                openWindowMenu(for: workspace)
            } else {
                showMenu(windows: nil)
            }
            return
        }
        switch layout.target(atButtonX: x, buttonWidth: width) {
        case .windowMenu(let workspace)?: openWindowMenu(for: workspace)
        case let target?: onClick?(target)
        case nil: break
        }
    }

    /// Reads the workspace's windows, then shows the menu with them on top.
    private func openWindowMenu(for workspace: WorkspaceName) {
        guard let readWindowMenu else { return }
        Task { [weak self] in
            guard let windows = await readWindowMenu(workspace) else { return }
            // Opened from the run loop rather than inside this task: the menu's tracking loop
            // runs until it closes, and refreshes on the main actor must keep running meanwhile.
            // Default mode only, so it waits for any other open menu to close instead of
            // opening inside it.
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated { self?.showMenu(windows: windows) }
            }
        }
    }

    private func showMenu(windows: WindowMenu?) {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        if let windows {
            addItems(for: windows, to: menu)
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        let launchAtLogin = LaunchAtLoginItem(status: SMAppService.mainApp.status)
        let login = menu.addItem(withTitle: launchAtLogin.title, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = launchAtLogin.state
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AeroSpaceIconz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + config.menuVerticalOffset), in: button)
    }

    /// The workspace header, then one row per window (or a disabled row saying why there are none).
    private func addItems(for windows: WindowMenu, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Workspace \(windows.workspace)"))
        guard let rows = windows.rows else {
            menu.addItem(withTitle: "Couldn't read windows", action: nil, keyEquivalent: "")
            return
        }
        if rows.isEmpty { menu.addItem(withTitle: "No windows", action: nil, keyEquivalent: "") }
        for row in rows {
            let item = menu.addItem(withTitle: row.label, action: #selector(chooseWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ChosenWindow(id: row.windowId, workspace: windows.workspace)
            item.image = menuIcon(for: row.app)
            item.state = row.isFocused ? .on : .off
        }
    }

    private struct ChosenWindow {
        var id: Int
        var workspace: WorkspaceName
    }

    private func menuIcon(for app: AppRef) -> NSImage {
        let icons = renderer.icons
        let icon = (icons.icon(for: app) ?? icons.fallback).copy() as! NSImage
        icon.size = NSSize(width: config.windowMenuIconSize, height: config.windowMenuIconSize)
        return icon
    }

    @objc private func chooseWindow(_ item: NSMenuItem) {
        guard let window = item.representedObject as? ChosenWindow else { return }
        onChooseWindow?(window.id, window.workspace)
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
