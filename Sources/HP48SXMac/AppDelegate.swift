import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let bridge = EmulatorBridge()
    var preferencesWindowController: PreferencesWindowController?

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
        // Stop the emulate thread BEFORE saving: write_files() reads the
        // live Saturn registers/memory, and the thread was still free to
        // mutate them concurrently if save() ran first -- a snapshot
        // torn mid-instruction. Matches restoreCheckpoint/fullReset's
        // existing stop-before-mutate ordering.
        bridge.stop()
        if UserDefaults.standard.bool(forKey: "saveOnExit", defaultValue: true) {
            bridge.save()
        }
    }
}

extension AppDelegate {
    @objc func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(bridge: bridge)
        }
        // Resync every time, not just at construction: a Restore
        // Checkpoint/Full Reset/Restore Backup since the window was last
        // shown may have changed the real port1/port2 files underneath it.
        preferencesWindowController?.refreshFromDisk()
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

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
        // Stop first -- see applicationWillTerminate's comment; the same
        // torn-snapshot risk applies to write_files() here.
        bridge.stop()
        bridge.save()
        try? AppPaths.standard.saveCheckpoint()
        bridge.start()
    }

    @objc func restoreCheckpoint() {
        guard confirm("Restore Checkpoint?", "This discards your current session and restores the last saved checkpoint.", actionTitle: "Restore") else { return }
        bridge.stop()
        try? AppPaths.standard.restoreCheckpoint()
        bridge.start()
        preferencesWindowController?.refreshFromDisk()
        notify("Checkpoint Restored")
    }

    @objc func fullReset() {
        guard confirm("Full Reset?", "This erases all memory and port cards. It cannot be undone.", actionTitle: "Reset") else { return }
        bridge.stop()
        try? AppPaths.standard.fullReset()
        bridge.start()
        preferencesWindowController?.refreshFromDisk()
        notify("Memory Reset")
    }

    @objc func saveBackupZip() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "48sx-backup.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Flush the CURRENT session to disk first, not whatever was there
        // from the last explicit save -- otherwise "Save Backup…" zips
        // stale state the user has no reason to expect.
        bridge.stop()
        bridge.save()
        do {
            try BackupZip.save(configDir: AppPaths.standard.configDir, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Backup Failed"
            alert.informativeText = "Could not write the backup zip."
            alert.runModal()
        }
        bridge.start()
    }

    @objc func restoreBackupZip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try BackupZip.validate(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Restore Failed"
            alert.informativeText = "This zip must contain hp48, ram, and rom."
            alert.runModal()
            return // never touched the running session
        }

        guard confirm("Restore Backup?", "This discards your current session and replaces it with the backup.", actionTitle: "Restore") else { return }
        bridge.stop()
        try? BackupZip.extract(from: url, into: AppPaths.standard.configDir)
        bridge.start()
        preferencesWindowController?.refreshFromDisk()
    }

    private func confirm(_ title: String, _ message: String, actionTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func notify(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
