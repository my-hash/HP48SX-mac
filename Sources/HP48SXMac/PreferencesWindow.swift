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
}

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Preferences"
        self.init(window: window)

        let saveOnExit = NSButton(checkboxWithTitle: "Save on Exit", target: self, action: #selector(toggleSaveOnExit))
        saveOnExit.state = UserDefaults.standard.bool(forKey: "saveOnExit", defaultValue: true) ? .on : .off
        saveOnExit.frame = NSRect(x: 20, y: 110, width: 280, height: 24)

        let port1Label = NSTextField(labelWithString: "Port 1:")
        port1Label.frame = NSRect(x: 20, y: 70, width: 60, height: 24)
        let port1Popup = NSPopUpButton(frame: NSRect(x: 90, y: 70, width: 120, height: 24))
        port1Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port1Popup.selectItem(at: UserDefaults.standard.string(forKey: "port1") == "128" ? 1 : 0)
        port1Popup.target = self
        port1Popup.action = #selector(port1Changed(_:))
        port1Popup.tag = 1

        let port2Label = NSTextField(labelWithString: "Port 2:")
        port2Label.frame = NSRect(x: 20, y: 30, width: 60, height: 24)
        let port2Popup = NSPopUpButton(frame: NSRect(x: 90, y: 30, width: 120, height: 24))
        port2Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port2Popup.selectItem(at: UserDefaults.standard.string(forKey: "port2") == "128" ? 1 : 0)
        port2Popup.target = self
        port2Popup.action = #selector(port2Changed(_:))
        port2Popup.tag = 2

        let contentView = NSView(frame: window.contentView!.frame)
        [saveOnExit, port1Label, port1Popup, port2Label, port2Popup].forEach(contentView.addSubview)
        window.contentView = contentView
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
        UserDefaults.standard.set(String(sizeKB), forKey: "port\(port)")
        try? PortCardManager.setSize(sizeKB, forPort: port, configDir: AppPaths.standard.configDir)
    }
}

// Not `private`: applicationWillTerminate (AppDelegate.swift, a different
// file) also needs this default-value accessor.
extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}
