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

    func testCreatedPortFileHasGroupWritePermissionSoPort1RegistersAsRAM() throws {
        // Final-review Important finding I4: init.c:1372 marks port1 as
        // RAM only if the file has the group-write bit set
        // (port1_is_ram = (st.st_mode & S_IWGRP) ? 1 : 0); Data.write(to:)
        // creates files at mode 0644 under the default umask, which does
        // NOT set S_IWGRP, so a "128kB" Port 1 card loaded as read-only
        // ROM instead of the writable RAM the user asked for. (Port 2
        // checks S_IWUSR instead, which 0644 already satisfies -- it's
        // unaffected, confirmed by init.c:1792's condition.)
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try PortCardManager.setSize(128, forPort: 1, configDir: dir)

        let attrs = try fm.attributesOfItem(atPath: dir.appendingPathComponent("port1").path)
        let mode = (attrs[.posixPermissions] as! NSNumber).uint16Value
        let S_IWGRP: UInt16 = 0o020
        XCTAssertNotEqual(mode & S_IWGRP, 0, "port1 needs the group-write bit set or init.c treats it as read-only ROM, not RAM")
    }
}
