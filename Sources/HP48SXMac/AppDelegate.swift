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

        NSApp.mainMenu = MenuBuilder(delegate: self).build()

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

extension AppDelegate {
    @objc func loadObject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if !bridge.loadObject(at: url) {
                let alert = NSAlert()
                alert.messageText = "Could not load \(url.lastPathComponent)"
                alert.informativeText = "This file couldn't be read."
                alert.runModal()
            }
        }
    }

    @objc func saveCheckpoint() {
        bridge.save()
        try? AppPaths.standard.saveCheckpoint()
    }

    @objc func restoreCheckpoint() {
        bridge.stop()
        try? AppPaths.standard.restoreCheckpoint()
        bridge.start()
    }

    @objc func fullReset() {
        bridge.stop()
        try? AppPaths.standard.fullReset()
        bridge.start()
    }

    @objc func saveBackupZip() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "48sx-backup.zip"
        if panel.runModal() == .OK, let url = panel.url {
            try? BackupZip.save(configDir: AppPaths.standard.configDir, to: url)
        }
    }

    @objc func restoreBackupZip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let url = panel.url {
            bridge.stop()
            do {
                try BackupZip.restore(from: url, into: AppPaths.standard.configDir)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Restore failed"
                alert.informativeText = "This zip must contain hp48, ram, and rom."
                alert.runModal()
            }
            bridge.start()
        }
    }
}
