import AppKit
import IconzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let config = Config.standard
    private var status: StatusController!
    private var coordinator: RefreshCoordinator!
    private var screenAsleep = false
    private var screenLocked = false
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusController(config: config)
        let client = CLIClient(candidates: config.aerospaceExecutableCandidates)
        coordinator = RefreshCoordinator(client: client, timing: config.timing) { [weak self] state in
            self?.status.render(state)
        }
        status.onSelectWorkspace = { [weak self] name in
            Task { await self?.coordinator.focus(workspace: name) }
        }
        status.onRefresh = { [weak self] in self?.coordinator.nudge() }

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
        // AeroSpace has no window-closed event; a quitting app is the most common case.
        workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.coordinator.nudge() }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreen(asleep: true) }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreen(asleep: false) }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreen(locked: true) }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setScreen(locked: false) }
        }
    }

    private func setScreen(asleep: Bool? = nil, locked: Bool? = nil) {
        if let asleep { screenAsleep = asleep }
        if let locked { screenLocked = locked }
        coordinator.setPaused(screenAsleep || screenLocked)
    }
}
