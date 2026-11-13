import AppKit

let application = NSApplication.shared
let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.wude.Soutujiang")
    .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if let existing {
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.wude.Soutujiang.show"), object: nil, userInfo: nil, deliverImmediately: true)
    existing.activate(options: [.activateIgnoringOtherApps])
} else {
    let delegate = AppController()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
