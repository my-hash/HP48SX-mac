import XCTest
@testable import HP48SXMac

/// Final-review Important finding I3: the spec requires "loadProg ->
/// auto-press ON" (matches upstream's HPView.pressON(), called from
/// X48.loadObject()/loadDocObject() on success: key(44,true);
/// Thread.sleep(200); key(44,false)). Without it, a loaded object sits on
/// the stack but the display never shows it -- Load Object silently does
/// nothing from the user's point of view.
final class LoadObjectAutoOnTests: XCTestCase {
    func testSuccessfulLoadTakesAtLeastAsLongAsThePressOnDelay() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        let deadline = Date().addingTimeInterval(2)
        while bridge.latestFrame() == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        let loadable = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "anything readable".data(using: .utf8)!.write(to: loadable)
        defer { try? fm.removeItem(at: loadable) }

        let start = Date()
        let ok = bridge.loadObject(at: loadable)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(ok, "setup: a readable file should load successfully (confirmed in EmulatorBridgeTests -- read_bin_file has no reject-content path)")
        XCTAssertGreaterThanOrEqual(elapsed, 0.15, "a successful load should auto-press ON (HPView.pressON()'s ~200ms key(44,true)/sleep/key(44,false)), not return instantly with no visible effect")
    }

    func testFailedLoadDoesNotPauseForPressOn() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        let deadline = Date().addingTimeInterval(2)
        while bridge.latestFrame() == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        let missing = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")

        let start = Date()
        let ok = bridge.loadObject(at: missing)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(ok)
        XCTAssertLessThan(elapsed, 0.1, "a failed load has nothing to show -- it should not pause for the auto-ON delay")
    }
}
