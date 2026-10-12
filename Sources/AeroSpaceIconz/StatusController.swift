import AppKit
import IconzCore
import ServiceManagement

/// Owns the status item: renders state, maps clicks to workspaces and app icons, shows the menu
/// (with the clicked pill's windows on top).
@MainActor
final class StatusController: NSObject {
    private let config: Config
    private let icons = IconCache()
    private let renderer: PillRenderer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var state: BarState = .unavailable
    /// What's currently drawn; used to map clicks to what they act on.
    private var layout: PillLayout
    private var appearanceObservation: NSKeyValueObservation?
    private var iconRetry: Task<Void, Never>?
    private var iconRetriesLeft = 0
    private var menuGate = MenuGate()

    var onSelect: ((Selection) -> Void)?
    var onRefresh: (() -> Void)?
    var readWindowMenu: ((WorkspaceName) async -> WindowMenu)?
    /// A window menu row was chosen: focus that window, on that workspace.
    var onChooseWindow: ((WindowId, WorkspaceName) -> Void)?

    init(config: Config) {
        self.config = config
        renderer = PillRenderer(config: config, icons: icons)
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
        let pillLeft = layout.pillLeft(atButtonX: x, buttonWidth: width) ?? 0
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            openMenu(for: layout.workspace(atButtonX: x, buttonWidth: width), pillLeft: pillLeft)
            return
        }
        switch layout.target(atButtonX: x, buttonWidth: width) {
        case .windowMenu(let workspace)?: openMenu(for: workspace, pillLeft: pillLeft)
        case .select(let selection)?: onSelect?(selection)
        case nil: break
        }
    }

    /// Shows the menu, with `workspace`'s windows on top (read first) when there is one, under
    /// the clicked pill (`pillLeft`, in button points). Ignored while another menu is opening or open.
    private func openMenu(for workspace: WorkspaceName?, pillLeft: Double) {
        guard menuGate.requestMenu() else { return }
        guard let workspace, let readWindowMenu else {
            showMenu(windows: nil, pillLeft: pillLeft)
            menuGate.menuClosed()
            return
        }
        Task { [weak self] in
            let windows = await readWindowMenu(workspace)
            // Opened from the run loop rather than inside this task: the menu's tracking loop
            // runs until it closes, and refreshes on the main actor must keep running meanwhile.
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    self?.showMenu(windows: windows, pillLeft: pillLeft)
                    self?.menuGate.menuClosed()
                }
            }
        }
    }

    /// Returns once the menu has closed. A window menu opens under its workspace's pill as
    /// drawn now (the read may have taken a refresh), else under the pill that was clicked.
    private func showMenu(windows: WindowMenu?, pillLeft clickedPillLeft: Double) {
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
        let pillLeft = windows.flatMap { layout.pillLeft(of: $0.workspace, buttonWidth: button.bounds.width) }
            ?? clickedPillLeft
        guard let window = button.window, let screen = window.screen else {
            menu.popUp(positioning: nil, at: NSPoint(x: pillLeft, y: button.bounds.height), in: button)
            return
        }
        let buttonOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = MenuOrigin(buttonMinX: buttonOnScreen.minX, pillLeft: pillLeft,
                                barBottom: window.frame.minY, visibleTop: screen.visibleFrame.maxY)
        menu.popUp(positioning: nil, at: NSPoint(x: origin.x, y: origin.y), in: nil)
    }

    /// The workspace header, then one row per window (or a disabled row saying why there are none).
    private func addItems(for windows: WindowMenu, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: windows.title))
        if let notice = windows.notice { menu.addItem(withTitle: notice, action: nil, keyEquivalent: "") }
        for row in windows.rows {
            let item = menu.addItem(withTitle: row.label, action: #selector(chooseWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ChosenWindow(id: row.windowId, workspace: windows.workspace)
            item.image = menuIcon(for: row.app)
            item.state = row.isFocused ? .on : .off
        }
    }

    private struct ChosenWindow {
        var id: WindowId
        var workspace: WorkspaceName
    }

    private func menuIcon(for app: AppRef) -> NSImage {
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
