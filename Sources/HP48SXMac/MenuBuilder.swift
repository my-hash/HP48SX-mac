import Cocoa

enum BackupZipError: Error { case missingRequiredMembers, zipFailed(Int32), unzipFailed(Int32) }

enum BackupZip {
    private static let members = ["hp48", "ram", "rom", "port1", "port2"]
    private static let requiredMembers = ["hp48", "ram", "rom"]

    static func save(configDir: URL, to destination: URL) throws {
        // /usr/bin/zip UPDATES an existing archive rather than replacing
        // it, so a member from an earlier save that's since been deleted
        // on disk (e.g. a removed port card) would otherwise survive
        // inside the zip forever. Start from a clean slate every time.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let present = members.filter { FileManager.default.fileExists(atPath: configDir.appendingPathComponent($0).path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = configDir
        process.arguments = ["-j", destination.path] + present
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BackupZipError.zipFailed(process.terminationStatus) }
    }

    static func validate(_ source: URL) throws {
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", source.path]
        let pipe = Pipe()
        listProcess.standardOutput = pipe
        try listProcess.run()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        listProcess.waitUntilExit()
        guard listProcess.terminationStatus == 0 else { throw BackupZipError.unzipFailed(listProcess.terminationStatus) }

        let names = Set(listing.split(separator: "\n").map(String.init))
        guard requiredMembers.allSatisfy(names.contains) else {
            throw BackupZipError.missingRequiredMembers
        }
    }

    static func extract(from source: URL, into configDir: URL) throws {
        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // Name the recognized members explicitly so restore only ever
        // writes these 5 files into configDir, never whatever else the
        // zip happens to contain; unzip silently skips names it doesn't
        // find, so listing all 5 is safe even when some are absent.
        extractProcess.arguments = ["-o", source.path] + members + ["-d", configDir.path]
        try extractProcess.run()
        extractProcess.waitUntilExit()
        // Naming all 5 members even though most backups only have 3
        // (no port cards) means unzip is told names it won't find --
        // that alone makes it exit 11 ("no matching files" for those
        // names specifically), not a real failure. Confirmed empirically:
        // the files that DO match still extract correctly either way.
        guard extractProcess.terminationStatus == 0 || extractProcess.terminationStatus == 11 else {
            throw BackupZipError.unzipFailed(extractProcess.terminationStatus)
        }
    }

    static func restore(from source: URL, into configDir: URL) throws {
        try validate(source)
        try extract(from: source, into: configDir)
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
