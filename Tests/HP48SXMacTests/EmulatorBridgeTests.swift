import XCTest
@testable import HP48SXMac

final class EmulatorBridgeTests: XCTestCase {
    func testStartProducesAFrameWithinTwoSeconds() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop() }

        let deadline = Date().addingTimeInterval(2)
        var frame: (screen: [UInt16], annunciators: [Bool])?
        while frame == nil, Date() < deadline {
            frame = bridge.latestFrame()
            if frame == nil { Thread.sleep(forTimeInterval: 0.05) }
        }

        XCTAssertNotNil(frame)
        XCTAssertTrue(frame!.screen.contains { $0 != 0 })
        try? fm.removeItem(at: dir)
    }

    func testPressKeyOutOfRangeDoesNotCrash() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()
        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        bridge.pressKey(999, down: true) // out of the 0...48 range
        bridge.pressKey(-1, down: true)
        // No crash = pass.
    }

    func testLoadObjectFailsForANonexistentFileWithoutCrashing() throws {
        // read_bin_file (binio.c) has no "reject bad content" path: a file
        // without HP48's "HPHP48-" magic header loads as a plain RPL
        // string object instead of failing (confirmed empirically -- a
        // garbage .txt file loads successfully, by design, the same way
        // the real calculator's ASCII transfer mode would). The only real
        // failure path is I/O: fopen/stat/malloc/fread/RPL_CreateTemp
        // failing, which a nonexistent path reliably exercises.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()
        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        let missing = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")

        let ok = bridge.loadObject(at: missing)

        XCTAssertFalse(ok, "read_bin_file should report failure when the file can't be opened")
    }

    func testStartHealsAZeroLengthStateFileFromCheckpointNotBareBundledDefaults() throws {
        // Review Focus item 1: a crash mid-write can leave a zero-length
        // ram/rom/hp48 file. X48.java's verifyNoFileZero() heals this via
        // restoreCheckpoint() specifically -- preserving whatever the user
        // last explicitly saved -- not by silently reverting to the
        // pristine bundled ROM/RAM (which would discard real progress).
        // AppPathsTests already proves the restore mechanism works in
        // isolation; this proves EmulatorBridge.start() actually wires it
        // in, and prefers the checkpoint over the bundled default.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets() // seeds checkpoint/ with the pristine copies

        // Simulate the user having saved a checkpoint after real progress:
        // overwrite the checkpoint's ram with distinguishable content.
        let distinctCheckpointRam = Data(repeating: 0xAB, count: 32 * 1024)
        try distinctCheckpointRam.write(to: paths.checkpointDir.appendingPathComponent("ram"))

        try Data().write(to: dir.appendingPathComponent("ram")) // simulate crash corruption
        XCTAssertFalse(paths.verifyNoZeroLengthFiles())

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        XCTAssertTrue(paths.verifyNoZeroLengthFiles(), "start() should have healed the zero-length file")
        let restoredRam = try Data(contentsOf: dir.appendingPathComponent("ram"))
        XCTAssertEqual(restoredRam, distinctCheckpointRam, "should restore from the checkpoint, not silently discard it for the bundled default")
    }
}
