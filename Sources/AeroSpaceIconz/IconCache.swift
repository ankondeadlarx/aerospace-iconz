import AppKit
import IconzCore

/// App icons by app key. Only real icons are cached, so an app whose icon isn't available
/// yet (still launching) is looked up again for the next image.
@MainActor
final class IconCache {
    private var icons: [AppKey: NSImage] = [:]
    private let lookup: @MainActor (AppRef) -> NSImage?
    /// Drawn in place of an icon that isn't available yet.
    private(set) lazy var fallback = NSWorkspace.shared.icon(for: .applicationBundle)

    init(lookup: @escaping @MainActor (AppRef) -> NSImage? = IconCache.systemIcon(for:)) {
        self.lookup = lookup
    }

    /// The app's icon, or `nil` if it isn't available yet.
    func icon(for app: AppRef) -> NSImage? {
        if let cached = icons[app.key] { return cached }
        guard let icon = lookup(app) else { return nil }
        icons[app.key] = icon
        return icon
    }

    /// The running app's icon (by pid), else the installed app's (by bundle id).
    static func systemIcon(for app: AppRef) -> NSImage? {
        NSRunningApplication(processIdentifier: app.pid)?.icon
            ?? app.bundleId
                .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
