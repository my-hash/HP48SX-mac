import XCTest
@testable import HP48SXMac

final class PortCardTests: XCTestCase {
    func testSettingPortSizeCreatesBlankFileOfExactSize() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try PortCardManager.setSize(128, forPort: 1, configDir: dir)

        let size = try fm.attributesOfItem(atPath: dir.appendingPathComponent("port1").path)[.size] as! Int
        XCTAssertEqual(size, 128 * 1024)
    }

    func testSettingPortSizeToZeroDeletesTheFile() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try PortCardManager.setSize(128, forPort: 2, configDir: dir)
        try PortCardManager.setSize(0, forPort: 2, configDir: dir)

        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("port2").path))
    }

    func testExistingCorrectSizedFileIsLeftUntouched() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let path = dir.appendingPathComponent("port1")
        try Data(repeating: 0xFF, count: 128 * 1024).write(to: path)

        try PortCardManager.setSize(128, forPort: 1, configDir: dir)

        let data = try Data(contentsOf: path)
        XCTAssertEqual(data.first, 0xFF, "an already-correct-size card must not be zeroed out")
    }
}
