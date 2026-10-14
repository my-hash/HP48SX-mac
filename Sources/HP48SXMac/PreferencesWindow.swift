import Cocoa

enum PortCardError: Error { case invalidPort }

enum PortCardManager {
    static func setSize(_ kb: Int, forPort port: Int, configDir: URL) throws {
        guard port == 1 || port == 2 else { throw PortCardError.invalidPort }
        let path = configDir.appendingPathComponent("port\(port)")
        let fm = FileManager.default

        if kb == 0 {
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
            return
        }

        let targetSize = kb * 1024
        if fm.fileExists(atPath: path.path),
           let existingSize = try? fm.attributesOfItem(atPath: path.path)[.size] as? Int,
           existingSize == targetSize {
            return
        }
        try Data(repeating: 0, count: targetSize).write(to: path)
        // init.c marks a port's card as writable RAM (vs. read-only ROM)
        // by checking a specific permission bit on the file itself --
        // port1 checks S_IWGRP, port2 checks S_IWUSR. Data.write(to:)
        // creates files at 0644 under the default umask, which already
        // satisfies S_IWUSR but not S_IWGRP, so port1 would otherwise
        // load as read-only. 0o664 sets both, covering either port.
        try fm.setAttributes([.posixPermissions: 0o664], ofItemAtPath: path.path)
    }

    /// The real on-disk truth for a port's card size, in kB (0 = no
    /// card). Preferences reads this fresh every time it's shown, rather
    /// than caching the user's last choice, so it can't go stale after
    /// Restore Checkpoint/Full Reset/Restore Backup changes the actual
    /// files underneath it.
    static func currentSizeKB(forPort port: Int, configDir: URL) -> Int {
        let path = configDir.appendingPathComponent("port\(port)")
        guard let size = try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? Int else {
            return 0
        }
        return size / 1024
    }
}

final class PreferencesWindowController: NSWindowController {
    private let bridge: EmulatorBridge
    private var port1Popup: NSPopUpButton!
    private var port2Popup: NSPopUpButton!

    convenience init(bridge: EmulatorBridge) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Preferences"
        self.init(window: window, bridge: bridge)

        let saveOnExit = NSButton(checkboxWithTitle: "Save on Exit", target: self, action: #selector(toggleSaveOnExit))
        saveOnExit.state = UserDefaults.standard.bool(forKey: "saveOnExit", defaultValue: true) ? .on : .off
        saveOnExit.frame = NSRect(x: 20, y: 110, width: 280, height: 24)

        let port1Label = NSTextField(labelWithString: "Port 1:")
        port1Label.frame = NSRect(x: 20, y: 70, width: 60, height: 24)
        port1Popup = NSPopUpButton(frame: NSRect(x: 90, y: 70, width: 120, height: 24))
        port1Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port1Popup.target = self
        port1Popup.action = #selector(port1Changed(_:))
        port1Popup.tag = 1

        let port2Label = NSTextField(labelWithString: "Port 2:")
        port2Label.frame = NSRect(x: 20, y: 30, width: 60, height: 24)
        port2Popup = NSPopUpButton(frame: NSRect(x: 90, y: 30, width: 120, height: 24))
        port2Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port2Popup.target = self
        port2Popup.action = #selector(port2Changed(_:))
        port2Popup.tag = 2

        let contentView = NSView(frame: window.contentView!.frame)
        [saveOnExit, port1Label, port1Popup, port2Label, port2Popup].forEach(contentView.addSubview)
        window.contentView = contentView

        refreshFromDisk()
    }

    private init(window: NSWindow?, bridge: EmulatorBridge) {
        self.bridge = bridge
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Re-reads the real port1/port2 files and resyncs the popups to
    /// match. Called on every open, not just construction, so a Restore
    /// Checkpoint/Full Reset/Restore Backup since this window was last
    /// shown can't leave it displaying a stale selection.
    func refreshFromDisk() {
        let configDir = AppPaths.standard.configDir
        port1Popup.selectItem(at: PortCardManager.currentSizeKB(forPort: 1, configDir: configDir) == 128 ? 1 : 0)
        port2Popup.selectItem(at: PortCardManager.currentSizeKB(forPort: 2, configDir: configDir) == 128 ? 1 : 0)
    }

    @objc private func toggleSaveOnExit(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "saveOnExit")
    }

    @objc private func port1Changed(_ sender: NSPopUpButton) {
        changePort(1, sizeKB: sender.indexOfSelectedItem == 1 ? 128 : 0)
    }

    @objc private func port2Changed(_ sender: NSPopUpButton) {
        changePort(2, sizeKB: sender.indexOfSelectedItem == 1 ? 128 : 0)
    }

    private func changePort(_ port: Int, sizeKB: Int) {
        // A port card's ROM-vs-RAM mapping is only decided when
        // init_emulator() boots, so a change here can't take effect on
        // the already-running emulator without a restart -- matching
        // upstream's own behavior ("forces a restart without saving").
        // Doing that restart immediately, with notice, beats the prior
        // behavior of silently writing the file and leaving the running
        // calculator on the old memory layout until the user happened to
        // relaunch by hand.
        try? PortCardManager.setSize(sizeKB, forPort: port, configDir: AppPaths.standard.configDir)
        bridge.stop()
        bridge.start()
        let alert = NSAlert()
        alert.messageText = "Port \(port) Updated"
        alert.informativeText = "Restarted the calculator to apply it. Anything not saved since your last Save Checkpoint was lost."
        alert.runModal()
    }
}

// Not `private`: applicationWillTerminate (AppDelegate.swift, a different
// file) also needs this default-value accessor.
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}
