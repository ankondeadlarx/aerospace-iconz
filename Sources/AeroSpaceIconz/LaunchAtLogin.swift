import AppKit
import ServiceManagement

/// The Launch at Login menu item for an `SMAppService.mainApp` status.
struct LaunchAtLoginItem: Equatable {
    enum Action: Equatable { case register, unregister, openSystemSettings }

    var title: String
    var state: NSControl.StateValue
    var action: Action

    init(status: SMAppService.Status) {
        switch status {
        case .enabled:
            (title, state, action) = ("Launch at Login", .on, .unregister)
        case .requiresApproval:
            // Registered, but the user has to allow it in System Settings › Login Items.
            (title, state, action) = ("Launch at Login (Allow in System Settings…)", .mixed, .openSystemSettings)
        default:
            (title, state, action) = ("Launch at Login", .off, .register)
        }
    }
}
