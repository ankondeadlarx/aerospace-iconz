import AppKit
import IconzCore

/// Debug modes that read the live AeroSpace, print what they made and exit, instead of
/// running the app:
///
/// - `AeroSpaceIconz --render-png <dir> [--mode <name>]`: renders the current state in light and
///   dark appearance to PNGs (creating `<dir>` if needed). `--mode` stands in for the binding
///   mode, to see the badge without entering that mode. For checking the drawing without
///   looking at the menu bar.
/// - `AeroSpaceIconz --print-window-menu <workspace>`: prints that workspace's window menu
///   (header, then focused mark, window id and label as shown per row). For checking the
///   menu's order and truncation against real titles without opening it.
@MainActor
enum DebugRender {
    static func runIfRequested() {
        run("--render-png", renderPNGs)
        run("--print-window-menu", printWindowMenu)
    }

    /// If `flag <argument>` was passed, runs `body` with the argument and exits with its status.
    private static func run(_ flag: String, _ body: @escaping @MainActor (String, Config, CLIClient) async -> Int32) {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return }
        let argument = arguments[index + 1]
        let config = Config.standard
        let client = CLIClient(candidates: config.aerospaceExecutableCandidates, timeout: config.cliTimeout)
        Task { @MainActor in exit(await body(argument, config, client)) }
        NSApplication.shared.run()
    }

    private static func renderPNGs(into path: String, config: Config, client: CLIClient) async -> Int32 {
        let directory = URL(fileURLWithPath: path)
        let arguments = CommandLine.arguments
        let modeOverride = arguments.firstIndex(of: "--mode").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }

        var state = BarState.unavailable
        await RefreshCoordinator(client: client, timing: config.timing) { state = $0 }.refresh()
        if state == .unavailable { print("AeroSpace not reachable: rendering the placeholder.") }
        if let modeOverride, case .workspaces(let groups, _) = state { state = .workspaces(groups, mode: modeOverride) }

        let renderer = PillRenderer(config: config, icons: IconCache())
        let image = renderer.image(for: renderer.layout(for: state)).image
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let url = directory.appendingPathComponent("pills-\(name).png")
                try write(image, appearance: NSAppearance(named: appearance)!, to: url)
                print(url.path)
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("--render-png failed: \(error)\n".utf8))
            return 1
        }
    }

    private static func printWindowMenu(for workspace: String, config: Config, client: CLIClient) async -> Int32 {
        let coordinator = RefreshCoordinator(
            client: client, timing: config.timing, maxTitleLength: config.windowMenuTitleLength
        ) { _ in }
        // A refresh first, so rows follow the pill's icon order as in the app.
        await coordinator.refresh()
        let menu = await coordinator.windowMenu(for: WorkspaceName(workspace))
        print(menu.title)
        if let notice = menu.notice { print("  \(notice)") }
        for row in menu.rows { print("\(row.isFocused ? "✓" : " ") \(row.windowId)\t\(row.label)") }
        return 0
    }

    private struct EncodingFailed: Error {}

    private static func write(_ image: NSImage, appearance: NSAppearance, to url: URL) throws {
        let scale = 2.0
        let size = NSSize(width: image.size.width + 16, height: image.size.height + 12)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            (appearance.name == .darkAqua ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            image.draw(in: NSRect(x: 8, y: 6, width: image.size.width, height: image.size.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { throw EncodingFailed() }
        try png.write(to: url)
    }
}
