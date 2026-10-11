import AppKit

DebugRender.runIfRequested()
DebugRender.printWindowMenuIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
