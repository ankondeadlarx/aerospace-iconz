import AppKit
import IconzCore

/// `AeroSpaceIconz --render-png <dir>`: renders the current AeroSpace state in light and
/// dark appearance to PNGs and exits. For checking the drawing without looking at the menu bar.
@MainActor
enum DebugRender {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-png"), flag + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        let config = Config.standard
        let client = CLIClient(candidates: config.aerospaceExecutableCandidates)

        Task { @MainActor in
            var reducer = WorkspaceReducer()
            let renderer = PillRenderer(config: config, icons: IconCache())
            let state: BarState = (try? await client.snapshot()).map { .workspaces(reducer.groups(for: $0)) } ?? .unavailable
            let layout = renderer.layout(for: state)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                write(renderer.image(for: layout), appearance: NSAppearance(named: appearance)!,
                      to: directory.appendingPathComponent("pills-\(name).png"))
            }
            exit(0)
        }
        NSApplication.shared.run()
    }

    private static func write(_ image: NSImage, appearance: NSAppearance, to url: URL) {
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
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
