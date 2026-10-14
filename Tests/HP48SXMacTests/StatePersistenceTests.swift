import XCTest
import CEmu
@testable import HP48SXMac

/// Final-review Critical finding C2: init_emulator() (init.c:1806-1826) has
/// two code paths and BOTH `return 0` -- there is no way to distinguish
/// "restored a saved session" from "fresh boot" via its return value.
/// EmulatorBridge used to treat `== 0` as "state didn't parse, needs
/// do_reset()", which fired on every single boot and re-defaulted the
/// memory controllers (do_reset(), actions.c) right after read_files()
/// had just restored them from the save file -- silently discarding a
/// real saved session every time the app relaunched.
final class StatePersistenceTests: XCTestCase {
    func testSecondBootDoesNotResetMemoryControllersAfterASuccessfulRestore() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        // "Session 1": boot, let the ROM finish its own power-on
        // configuration, then save.
        let bridge1 = EmulatorBridge(paths: paths)
        bridge1.start()
        waitForFirstFrame(bridge1)
        bridge1.save()
        bridge1.stop()

        let configuredAfterFirstBoot = emu_debug_mem_cntl_unconfigured(0)
        XCTAssertEqual(configuredAfterFirstBoot, 0, "the ROM's own boot code should have configured controller 0 by now")

        // "Session 2": a fresh EmulatorBridge instance against the same
        // saved files, simulating an app relaunch. If do_reset() fires
        // unconditionally, this re-defaults controller 0 right after
        // read_files() restored it.
        let bridge2 = EmulatorBridge(paths: paths)
        bridge2.start()
        waitForFirstFrame(bridge2)
        defer { bridge2.stop() }

        XCTAssertEqual(emu_debug_mem_cntl_unconfigured(0), 0, "a relaunch that successfully restored saved state must not re-default the memory controller")
    }

    private func waitForFirstFrame(_ bridge: EmulatorBridge) {
        let deadline = Date().addingTimeInterval(2)
        while bridge.latestFrame() == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
