import XCTest
@testable import HP48SXMac

final class AppPathsTests: XCTestCase {
    var paths: AppPaths!
    var tmpRoot: URL!

    override func setUpWithError() throws {
        tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        paths = AppPaths(configDir: tmpRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpRoot)
    }

    func testFirstRunCopiesBundledAssetsAndChecksSize() throws {
        try paths.ensureFirstRunAssets()

        let rom = tmpRoot.appendingPathComponent("rom")
        let ram = tmpRoot.appendingPathComponent("ram")
        let hp48 = tmpRoot.appendingPathComponent("hp48")
        let sizes = try [rom, ram, hp48].map {
            try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as! Int
        }

        XCTAssertEqual(sizes[0], 256 * 1024, "rom must be exactly 256KB")
        XCTAssertEqual(sizes[1], 32 * 1024, "ram must be exactly 32KB")
        XCTAssertGreaterThan(sizes[2], 0, "hp48 state file must be non-empty")

        // Also seeds the checkpoint/ auto-backup on first run.
        let checkpointRom = tmpRoot.appendingPathComponent("checkpoint/rom")
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpointRom.path))
    }

    func testZeroLengthFileTriggersRestoreCheckpoint() throws {
        try paths.ensureFirstRunAssets()
        // Simulate a crash-corrupted state file.
        try Data().write(to: tmpRoot.appendingPathComponent("ram"))

        XCTAssertFalse(paths.verifyNoZeroLengthFiles())
        try paths.restoreCheckpoint()
        XCTAssertTrue(paths.verifyNoZeroLengthFiles())

        let ramSize = try FileManager.default.attributesOfItem(
            atPath: tmpRoot.appendingPathComponent("ram").path)[.size] as! Int
        XCTAssertEqual(ramSize, 32 * 1024)
    }

    func testFullResetDeletesStateAndReCopiesBundledAssets() throws {
        try paths.ensureFirstRunAssets()
        try "garbage".data(using: .utf8)!.write(to: tmpRoot.appendingPathComponent("ram"))

        try paths.fullReset()

        let ramSize = try FileManager.default.attributesOfItem(
            atPath: tmpRoot.appendingPathComponent("ram").path)[.size] as! Int
        XCTAssertEqual(ramSize, 32 * 1024, "full reset re-copies the pristine bundled ram image")
    }

    func testSaveCheckpointOverwritesWithCurrentState() throws {
        try paths.ensureFirstRunAssets()
        try Data(repeating: 0xAB, count: 32 * 1024).write(to: tmpRoot.appendingPathComponent("ram"))

        try paths.saveCheckpoint()

        let checkpointRam = try Data(contentsOf: tmpRoot.appendingPathComponent("checkpoint/ram"))
        XCTAssertEqual(checkpointRam, Data(repeating: 0xAB, count: 32 * 1024))
    }
}
