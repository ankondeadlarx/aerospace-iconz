import AppKit
import IconzCore

/// App icons by app key. Only real icons are cached, so an app whose icon wasn't
/// available yet (still launching) gets another try on the next draw.
@MainActor
final class IconCache {
    private var icons: [AppKey: NSImage] = [:]
    private lazy var fallback = NSWorkspace.shared.icon(for: .applicationBundle)

    func icon(for app: AppRef) -> NSImage {
        if let cached = icons[app.key] { return cached }
        let icon = NSRunningApplication(processIdentifier: app.pid)?.icon
            ?? app.bundleId
                .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        guard let icon else { return fallback }
        icons[app.key] = icon
        return icon
    }
}
