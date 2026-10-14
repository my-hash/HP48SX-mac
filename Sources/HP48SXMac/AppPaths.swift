import Foundation

/// Ports X48.java's AssetUtil + checkpoint/full-reset/zero-length-guard
/// logic. `configDir` is injectable for testing; production code uses
/// AppPaths.standard (~/Library/Application Support/HP48SX/).
struct AppPaths {
    static let standard = AppPaths(
        configDir: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HP48SX", isDirectory: true)
    )

    let configDir: URL
    private static let stateFiles = ["hp48", "ram", "rom"]
    private static let requiredSize: [String: Int] = ["ram": 32 * 1024, "rom": 256 * 1024]

    /// Path string for emu_set_config_dir -- must end in "/".
    var configDirPath: String { configDir.path + "/" }

    var checkpointDir: URL { configDir.appendingPathComponent("checkpoint", isDirectory: true) }

    func ensureFirstRunAssets() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        for name in Self.stateFiles {
            let dest = configDir.appendingPathComponent(name)
            let required = Self.requiredSize[name]
            let needsCopy = !fm.fileExists(atPath: dest.path)
                || (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) == 0
                || (required != nil && (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) != required)
            if needsCopy {
                let src = Bundle.module.url(forResource: name, withExtension: nil)!
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: src, to: dest)
            }
        }

        if !fm.fileExists(atPath: checkpointDir.path) {
            try fm.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
            for name in Self.stateFiles {
                try fm.copyItem(at: configDir.appendingPathComponent(name),
                                 to: checkpointDir.appendingPathComponent(name))
            }
        }
    }

    func verifyNoZeroLengthFiles() -> Bool {
        let fm = FileManager.default
        for name in Self.stateFiles {
            let path = configDir.appendingPathComponent(name).path
            if fm.fileExists(atPath: path),
               let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int,
               size == 0 {
                return false
            }
        }
        return true
    }

    func saveCheckpoint() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
        for name in Self.stateFiles + ["port1", "port2"] {
            let src = configDir.appendingPathComponent(name)
            let dst = checkpointDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: dst) }
        }
    }

    func restoreCheckpoint() throws {
        let fm = FileManager.default
        for name in Self.stateFiles + ["port1", "port2"] {
            let dst = configDir.appendingPathComponent(name)
            let src = checkpointDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: dst) }
        }
    }

    func fullReset() throws {
        let fm = FileManager.default
        for name in Self.stateFiles + ["port1", "port2"] {
            let path = configDir.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
        }
        try ensureFirstRunAssets()
    }
}
