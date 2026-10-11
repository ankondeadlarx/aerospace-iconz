import AppKit
import ServiceManagement
import Testing
@testable import AeroSpaceIconz

@MainActor @Suite struct LaunchAtLoginTests {
    @Test func enabledIsCheckedAndTurnsOff() {
        let item = LaunchAtLoginItem(status: .enabled)
        #expect(item.state == .on)
        #expect(item.action == .unregister)
    }

    @Test func offIsUncheckedAndTurnsOn() {
        for status in [SMAppService.Status.notRegistered, .notFound] {
            let item = LaunchAtLoginItem(status: status)
            #expect(item.state == .off)
            #expect(item.action == .register)
        }
    }

    /// Registered, but the user still has to allow it in System Settings › Login Items.
    @Test func awaitingApprovalSaysSoAndOpensSystemSettings() {
        let item = LaunchAtLoginItem(status: .requiresApproval)
        #expect(item.state == .mixed)
        #expect(item.action == .openSystemSettings)
        #expect(item.title != LaunchAtLoginItem(status: .enabled).title)
    }
}
