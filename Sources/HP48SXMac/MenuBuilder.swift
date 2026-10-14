import Cocoa

enum BackupZipError: Error { case missingRequiredMembers }

enum BackupZip {
    private static let members = ["hp48", "ram", "rom", "port1", "port2"]

    static func save(configDir: URL, to destination: URL) throws {
        let present = members.filter { FileManager.default.fileExists(atPath: configDir.appendingPathComponent($0).path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = configDir
        process.arguments = ["-j", destination.path] + present
        try process.run()
        process.waitUntilExit()
    }

    static func restore(from source: URL, into configDir: URL) throws {
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", source.path]
        let pipe = Pipe()
        listProcess.standardOutput = pipe
        try listProcess.run()
        listProcess.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let names = Set(listing.split(separator: "\n").map(String.init))

        guard names.contains("hp48"), names.contains("ram"), names.contains("rom") else {
            throw BackupZipError.missingRequiredMembers
        }

        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extractProcess.arguments = ["-o", source.path, "-d", configDir.path]
        try extractProcess.run()
        extractProcess.waitUntilExit()
    }
}

final class MenuBuilder {
    private unowned let delegate: AppDelegate

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func build() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Preferences…", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit 48SX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let calcMenuItem = NSMenuItem()
        let calcMenu = NSMenu(title: "Calculator")
        calcMenu.addItem(withTitle: "Load Object…", action: #selector(AppDelegate.loadObject), keyEquivalent: "o")
        calcMenu.addItem(.separator())
        calcMenu.addItem(withTitle: "Save Checkpoint", action: #selector(AppDelegate.saveCheckpoint), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Restore Checkpoint", action: #selector(AppDelegate.restoreCheckpoint), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Full Reset (Memory)", action: #selector(AppDelegate.fullReset), keyEquivalent: "")
        calcMenu.addItem(.separator())
        calcMenu.addItem(withTitle: "Save Backup…", action: #selector(AppDelegate.saveBackupZip), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Restore Backup…", action: #selector(AppDelegate.restoreBackupZip), keyEquivalent: "")
        calcMenuItem.submenu = calcMenu
        mainMenu.addItem(calcMenuItem)

        return mainMenu
    }
}
