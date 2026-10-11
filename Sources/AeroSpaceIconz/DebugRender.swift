import AppKit
import IconzCore

/// `AeroSpaceIconz --render-png <dir> [--mode <name>]`: renders the current AeroSpace state in
/// light and dark appearance to PNGs (creating `<dir>` if needed) and exits. `--mode` stands
/// in for the binding mode, to see the badge without entering that mode. For checking the
/// drawing without looking at the menu bar.
@MainActor
enum DebugRender {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-png"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        let modeOverride = arguments.firstIndex(of: "--mode").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        let config = Config.standard
        let client = CLIClient(candidates: config.aerospaceExecutableCandidates, timeout: config.cliTimeout)

        Task { @MainActor in
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
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("--render-png failed: \(error)\n".utf8))
                exit(1)
            }
        }
        NSApplication.shared.run()
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
