import AppKit
import IconzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = Config.standard
    private var status: StatusController!
    private var coordinator: RefreshCoordinator!
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusController(config: config)
        let client = CLIClient(candidates: config.aerospaceExecutableCandidates, timeout: config.cliTimeout)
        coordinator = RefreshCoordinator(
            client: client, timing: config.timing, maxTitleLength: config.windowMenuTitleLength
        ) { [weak self] state in
            self?.status.render(state)
        }
        status.onSelect = { [weak self] selection in
            Task { await self?.coordinator.select(selection) }
        }
        status.onRefresh = { [weak self] in self?.coordinator.nudge() }
        status.readWindowMenu = { [weak self] workspace in
            await self?.coordinator.windowMenu(for: workspace) ?? .unreadable(workspace)
        }
        status.onChooseWindow = { [weak self] id, workspace in
            Task { await self?.coordinator.focus(windowId: id, on: workspace) }
        }

        observeSystem()
        handleSIGTERM()
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        Subscriptions.terminateAll()
    }

    /// `pkill` / logout send SIGTERM, which skips applicationWillTerminate by default.
    private func handleSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        // AeroSpace has no window-closed event; a quitting app is the most common case.
        observe(NSWorkspace.didTerminateApplicationNotification, on: workspace) { $0.nudge() }
        observe(NSWorkspace.screensDidSleepNotification, on: workspace) { $0.setPaused(true, for: .displaysAsleep) }
        observe(NSWorkspace.screensDidWakeNotification, on: workspace) { $0.setPaused(false, for: .displaysAsleep) }
        observe(.init("com.apple.screenIsLocked"), on: distributed) { $0.setPaused(true, for: .screenLocked) }
        observe(.init("com.apple.screenIsUnlocked"), on: distributed) { $0.setPaused(false, for: .screenLocked) }
    }

    private func observe(
        _ name: Notification.Name, on center: NotificationCenter,
        _ action: @escaping @MainActor (RefreshCoordinator) -> Void
    ) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let coordinator = self?.coordinator { action(coordinator) }
            }
        }
    }
}
