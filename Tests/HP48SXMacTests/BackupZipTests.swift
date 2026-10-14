import XCTest
@testable import HP48SXMac

final class BackupZipTests: XCTestCase {
    func testSaveThenRestoreRoundTrips() throws {
        let fm = FileManager.default
        let configDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        try "romdata".data(using: .utf8)!.write(to: configDir.appendingPathComponent("rom"))
        try "ramdata".data(using: .utf8)!.write(to: configDir.appendingPathComponent("ram"))
        try "hp48data".data(using: .utf8)!.write(to: configDir.appendingPathComponent("hp48"))

        let zipPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try BackupZip.save(configDir: configDir, to: zipPath)
        XCTAssertTrue(fm.fileExists(atPath: zipPath.path))

        let restoreDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        try BackupZip.restore(from: zipPath, into: restoreDir)

        let restoredRom = try String(contentsOf: restoreDir.appendingPathComponent("rom"), encoding: .utf8)
        XCTAssertEqual(restoredRom, "romdata")

        try? fm.removeItem(at: configDir)
        try? fm.removeItem(at: zipPath)
        try? fm.removeItem(at: restoreDir)
    }

    func testRestoreRejectsZipMissingRequiredMembers() throws {
        let fm = FileManager.default
        let emptyDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        try "unrelated".data(using: .utf8)!.write(to: emptyDir.appendingPathComponent("notes.txt"))

        let zipPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try BackupZip.save(configDir: emptyDir, to: zipPath) // zips just notes.txt

        let restoreDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BackupZip.restore(from: zipPath, into: restoreDir))

        try? fm.removeItem(at: emptyDir)
        try? fm.removeItem(at: zipPath)
        try? fm.removeItem(at: restoreDir)
    }
}

extension BackupZipTests {
    func testFullResetStopsEmulatorBeforeTouchingFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        Thread.sleep(forTimeInterval: 0.1) // let the loop actually spin up

        // The menu action must stop the bridge before AppPaths.fullReset()
        // touches files the background thread might still be reading. This
        // ordering is what MenuBuilder's "Full Reset" action implements;
        // this test exercises AppPaths directly to prove it's safe even if
        // called mid-cycle, not just in the already-stopped case.
        bridge.stop()
        try paths.fullReset()

        let ramSize = try fm.attributesOfItem(atPath: dir.appendingPathComponent("ram").path)[.size] as! Int
        XCTAssertEqual(ramSize, 32 * 1024)
        try? fm.removeItem(at: dir)
    }

    func testStopActuallyWaitsForTheEmulateThreadToFinish() throws {
        // Final-review Important finding I5: the test above only proves
        // the *result* (files end up the right size) is safe, which it
        // would be even if stop() were a no-op racing a thread that
        // happens to finish on its own in time. It doesn't prove stop()
        // itself guarantees the thread is done -- a fixed sleep(0.1)
        // doesn't guarantee that under load, and gave no way to tell the
        // difference between "waited and it finished" and "slept and
        // got lucky". stop() now waits on a semaphore the emulate thread
        // signals when its loop actually exits, and records whether it
        // really observed that (vs. timing out) for exactly this check.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()
        defer { try? fm.removeItem(at: dir) }

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        Thread.sleep(forTimeInterval: 0.1)

        bridge.stop()

        XCTAssertEqual(bridge.lastStopObservedThreadFinished, true, "stop() should have actually observed the emulate thread finish, not just returned after a fixed delay")
    }
}
