import XCTest
import CEmu
@testable import HP48SXMac

/// Final-review Important finding I1: upstream's main loop is
/// `do { emulate()/emulate_debug(); debug(); } while (exit_state)`.
/// emulate() returns early when `enter_debugger` becomes non-zero (an
/// illegal instruction or TRAP, per emulate.c's own loop condition
/// "while (!enter_debugger && exit_state)"); debug(), with useDebugger
/// == 0 (its real default -- no task ever turns the interactive debugger
/// on), recovers by resetting PC to 0 and returning (debugger.c:1672-1693),
/// and upstream's outer loop then calls emulate() again. EmulatorBridge
/// called emulate() exactly once with no outer loop, so that recovery
/// never got a chance to run: any illegal instruction permanently ends
/// the emulate thread, freezing the calculator until relaunch.
final class CrashRecoveryTests: XCTestCase {
    func testEmulationContinuesAfterAnIllegalInstructionTrap() throws {
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
        XCTAssertNotNil(bridge.latestFrame(), "setup: should have booted at all")

        // debugLoopIterations only increments when the outer repeat-while
        // calls debug() after emulate() returns -- which, in normal
        // operation, never happens (emulate() blocks inside its own
        // do-while for the entire session; see EmulatorBridge's doc
        // comment). It's 0 before any fault.
        XCTAssertEqual(bridge.debugLoopIterations, 0, "setup: debug() should not have run yet, nothing has faulted")

        // The CPU spends almost all of its time idle (SHUTDN), sitting
        // inside do_shutdown()'s own inner wait loop (actions.c), which
        // does NOT check enter_debugger at all -- it only "wakes" on a
        // real emulated timer tick or interrupt, and returns to SHUTDN
        // again within, at most, a handful of instructions once whatever
        // woke it is handled. So the window where the outer emulate()
        // loop is actively executing instructions (and therefore checks
        // enter_debugger at all) is brief and not reliably hittable with
        // a single injection at an arbitrary time (confirmed empirically:
        // a single injection worked once out of many attempts). Keep
        // re-injecting in a loop, interleaved with key presses to keep
        // waking the CPU, until it lands -- this only needs the active
        // window to recur at all, not to be hit on the first try.
        let deadline2 = Date().addingTimeInterval(3)
        while bridge.debugLoopIterations == 0, Date() < deadline2 {
            bridge.pressKey(40, down: true) // digit "1", just to force activity
            bridge.pressKey(40, down: false)
            emu_debug_trigger_illegal_instruction()
            Thread.sleep(forTimeInterval: 0.01)
        }

        // debug()'s recovery resets PC to 0, which with the Saturn CPU's
        // *other* registers left in whatever state they were in
        // mid-execution can itself cascade into further faults -- this
        // can legitimately produce more than one loop iteration, which is
        // fine: debugLoopIterations only needs to be > 0 to prove the
        // outer loop is demonstrably running debug() and retrying, not
        // that it settles afterward.
        XCTAssertGreaterThan(bridge.debugLoopIterations, 0, "the outer loop should have called debug() at least once after the injected fault; 0 means emulate() returned and the thread simply ended (the original bug)")
    }
}
