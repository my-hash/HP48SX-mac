import CEmu
import Foundation

/// Drives the vendored Saturn-CPU core. `emulate()`/`emulate_debug()` are
/// NOT per-frame calls -- emulate.c's own loop ("while (!enter_debugger &&
/// exit_state)") runs continuously with no throttling until exit_state is
/// set to 0, so it is started exactly once on a dedicated thread and left
/// running for the app's whole lifetime. A second, independent thread
/// polls emu_fill_screen_data() at 25fps (matching HPView.run()'s
/// Thread.sleep(40) on Android) to keep `latestFrame()` fresh -- the real
/// architecture always had two threads (EmulatorThread + HPView's draw
/// thread), not one thread doing both jobs.
final class EmulatorBridge {
    private let paths: AppPaths
    private var emulateThread: Thread?
    private var pollThread: Thread?
    private var pollRunning = false
    private let frameLock = NSLock()
    private var frame: (screen: [UInt16], annunciators: [Bool])?
    private let emulateThreadFinished = DispatchSemaphore(value: 0)

    /// Test-only: whether the most recent stop() actually observed the
    /// emulate thread finish (vs. timing out and returning anyway). nil
    /// before any stop() call.
    private(set) var lastStopObservedThreadFinished: Bool?

    /// Counts how many times the outer repeat-while loop has called
    /// debug() -- i.e. how many times emulate()/emulate_debug() has
    /// returned early and been retried. Zero for the entire normal
    /// session (emulate() only returns on a fault or exit_state == 0);
    /// test-only visibility into whether a fault was actually recovered
    /// from, without racing an oscillating C global (see
    /// CrashRecoveryTests for why that polling approach doesn't work).
    /// Locked (not just a plain var) because it's written on the emulate
    /// thread and read from tests on a different thread.
    private let debugLoopIterationsLock = NSLock()
    private var _debugLoopIterations = 0
    var debugLoopIterations: Int {
        debugLoopIterationsLock.lock()
        defer { debugLoopIterationsLock.unlock() }
        return _debugLoopIterations
    }

    init(paths: AppPaths = .standard) {
        self.paths = paths
    }

    func start() {
        guard emulateThread == nil else { return }

        // A crash mid-write can leave a zero-length state file. Heal from
        // the checkpoint (preserving whatever the user last explicitly
        // saved) BEFORE ensureFirstRunAssets(), which would otherwise see
        // the same zero-length file and silently overwrite it with the
        // pristine bundled default, discarding real progress.
        if !paths.verifyNoZeroLengthFiles() {
            try? paths.restoreCheckpoint()
        }
        try? paths.ensureFirstRunAssets()
        emu_set_config_dir(paths.configDirPath)
        // init_emulator() (init.c) always returns 0 -- both its
        // "successfully restored saved state" and "fresh boot" paths end
        // in `return 0`, so its return value can't signal failure. Call
        // it bare, matching upstream's own usage (main.c's original
        // `init_emulator();`, return value discarded). Do NOT follow it
        // with do_reset() here: that unconditionally re-defaults the
        // memory controllers, which silently discards a just-restored
        // saved session (confirmed: a relaunch lost the RPL stack).
        _ = init_emulator()
        init_active_stuff()
        // Matches HPView's constructor calling x48.setBlankColor with
        // contrast "1" (the real default -- nothing here ever sets a
        // different value): contrast_factor 0.5 -> (23<<11)+(48<<5)+20 =
        // 0xBE14. Without this, the icon strip (disp_buf_header_short)
        // stays all-zero/black, so the annunciator icons are invisible
        // and the LCD background is the wrong color.
        emu_set_blank_color(0xBE14)

        exit_state = 1
        let emuThread = Thread { [weak self] in
            // Matches upstream's main loop exactly:
            // do { emulate()/emulate_debug(); debug(); } while (exit_state).
            // emulate() returns early when enter_debugger goes non-zero
            // (an illegal instruction or TRAP -- see its own loop
            // condition, "while (!enter_debugger && exit_state)"); debug()
            // (useDebugger is 0 by default, confirmed -- no task ever
            // turns the interactive debugger on) recovers by resetting PC
            // to 0 and clearing enter_debugger, and the loop continues.
            // Calling emulate() exactly once with no outer loop meant any
            // illegal instruction permanently ended this thread, freezing
            // the calculator until relaunch.
            repeat {
                if exec_flags == 0 { _ = emulate() } else { _ = emulate_debug() }
                _ = debug()
                if let self {
                    self.debugLoopIterationsLock.lock()
                    self._debugLoopIterations += 1
                    self.debugLoopIterationsLock.unlock()
                }
            } while exit_state != 0
            self?.emulateThreadFinished.signal()
        }
        emuThread.name = "HP48SXMac.emulate"
        emuThread.start()
        emulateThread = emuThread

        pollRunning = true
        let poller = Thread { [weak self] in
            while self?.pollRunning == true {
                self?.pollFrame()
                Thread.sleep(forTimeInterval: 1.0 / 25.0)
            }
        }
        poller.name = "HP48SXMac.poll"
        poller.start()
        pollThread = poller
    }

    func stop() {
        guard emulateThread != nil else { return }
        exit_state = 0
        pollRunning = false
        // Actually wait for the emulate thread to finish instead of
        // guessing a fixed sleep: emulate()'s do-while checks exit_state
        // after every instruction (or at most every ~20ms while idle in
        // do_shutdown()'s own "while (wake == 0 && exit_state)" loop), so
        // this normally returns almost immediately: a bounded 2s timeout
        // is just a safety net against ever blocking forever, in case
        // something keeps the thread from reaching its exit check at
        // all. A fresh start() right after stop() returns can then
        // safely touch the same C globals -- there is only one Saturn
        // CPU state per process -- without racing the previous run's
        // tail end.
        lastStopObservedThreadFinished = emulateThreadFinished.wait(timeout: .now() + 2) == .success
        emulateThread = nil
        pollThread = nil
    }

    func save() {
        _ = write_files()
    }

    /// Matches HPView.key(): queues the code (down -> code+1, up ->
    /// code+100) for emulate()'s GetEvent()/key_event() to pick up, and
    /// force-flags a redraw the same way HPView.key() calls
    /// x48.flipScreen() -- so a keypress shows up immediately rather than
    /// waiting for the ROM's own next natural redraw.
    func pressKey(_ code: Int32, down: Bool) {
        guard (0..<49).contains(code) else { return }
        HostKeyQueue.shared.pressKey(code, down: down)
        emu_flip_screen()
    }

    func loadObject(at url: URL) -> Bool {
        let ok = url.withUnsafeFileSystemRepresentation { ptr -> Bool in
            guard let ptr else { return false }
            return read_bin_file(UnsafeMutablePointer(mutating: ptr)) == 1
        }
        if ok {
            // Matches HPView.pressON(), called by X48.loadObject()/
            // loadDocObject() on success: the loaded object sits on the
            // RPL stack but the display never shows it without this --
            // Load Object would otherwise silently appear to do nothing.
            pressKey(44, down: true)
            Thread.sleep(forTimeInterval: 0.2)
            pressKey(44, down: false)
        }
        return ok
    }

    func latestFrame() -> (screen: [UInt16], annunciators: [Bool])? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return frame
    }

    private func pollFrame() {
        var buf = [UInt16](repeating: 0, count: Int(EMU_SCREEN_BUF_LEN))
        var annBytes = [UInt8](repeating: 0, count: 6)
        let got = buf.withUnsafeMutableBufferPointer { bufPtr in
            annBytes.withUnsafeMutableBufferPointer { annPtr in
                emu_fill_screen_data(bufPtr.baseAddress, annPtr.baseAddress)
            }
        }
        if got == 1 {
            frameLock.lock()
            frame = (buf, annBytes.map { $0 != 0 })
            frameLock.unlock()
        }
    }
}
