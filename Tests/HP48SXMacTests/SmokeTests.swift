import XCTest
import CEmu
@testable import HP48SXMac

final class SmokeTests: XCTestCase {
    func testEmulatorBootsAndProducesScreenData() throws {
        // Fresh config dir per test run, seeded from the bundled assets.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // Bundle.module isn't visible here: it's synthesized per-target, and
        // a `@testable import` of an executableTarget doesn't expose its
        // resource-bundle accessor to a different target's test files.
        // Resolve the repo's checked-in Resources/ directly instead.
        let resourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HP48SXMacTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Sources/HP48SXMac/Resources")
        for name in ["rom", "ram", "hp48"] {
            let src = resourcesDir.appendingPathComponent(name)
            try fm.copyItem(at: src, to: dir.appendingPathComponent(name))
        }

        emu_set_config_dir(dir.path + "/")
        // init_emulator() always returns 0 regardless of outcome (both its
        // code paths end `return 0`) -- call it bare, matching upstream;
        // see EmulatorBridge.start() and StatePersistenceTests for why a
        // do_reset() fallback here would be actively wrong.
        _ = init_emulator()
        init_active_stuff()

        // emulate()'s own do-while loop (emulate.c) runs continuously --
        // "while (!enter_debugger && exit_state)" -- executing Saturn
        // instructions as fast as possible until told to stop. It is not
        // a "run a batch of cycles and return" call: it's the main loop,
        // meant to be called once on a dedicated thread for the app's
        // whole lifetime (exactly how EmulatorBridge runs it). So this
        // test runs it on a background thread, lets real wall-clock time
        // pass for it to actually boot the ROM, then asks it to stop by
        // setting exit_state = 0 (the same global main.c's old JNI
        // stopHPEmulator() used to flip).
        exit_state = 1
        let thread = Thread {
            if exec_flags == 0 { _ = emulate() } else { _ = emulate_debug() }
        }
        thread.start()
        Thread.sleep(forTimeInterval: 0.5)

        emu_flip_screen()
        var buf = [UInt16](repeating: 0, count: Int(EMU_SCREEN_BUF_LEN))
        var ann = [UInt8](repeating: 0, count: 6)
        let got = buf.withUnsafeMutableBufferPointer { bufPtr in
            ann.withUnsafeMutableBufferPointer { annPtr in
                emu_fill_screen_data(bufPtr.baseAddress, annPtr.baseAddress)
            }
        }

        exit_state = 0
        Thread.sleep(forTimeInterval: 0.1) // let the loop notice and return

        XCTAssertEqual(got, 1, "emu_fill_screen_data should report a fresh frame")
        XCTAssertTrue(buf.contains { $0 != 0 }, "screen buffer should not be all zero after boot")
    }
}
