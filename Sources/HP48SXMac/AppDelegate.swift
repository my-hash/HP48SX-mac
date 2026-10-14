import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let bridge = EmulatorBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge.start()

        let contentRect = NSRect(origin: .zero, size: KeyLayout.contentSize)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "48SX"
        window.isRestorable = false
        window.contentView = CalculatorView(frame: contentRect, bridge: bridge)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.save()
        bridge.stop()
    }
}
