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

    init(paths: AppPaths = .standard) {
        self.paths = paths
    }

    func start() {
        guard emulateThread == nil else { return }

        emu_set_config_dir(paths.configDirPath)
        if init_emulator() == 0 {
            // Fresh/placeholder state file didn't parse; reset to a known-good state.
            do_reset()
        }
        init_active_stuff()

        exit_state = 1
        let emuThread = Thread {
            if exec_flags == 0 { _ = emulate() } else { _ = emulate_debug() }
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
        // emulate()'s do-while checks exit_state after every instruction,
        // so this is generous; it just keeps a fresh start() right after
        // from racing the previous run's tail end (both touch the same C
        // globals -- there is only one Saturn CPU state per process).
        Thread.sleep(forTimeInterval: 0.1)
        emulateThread = nil
        pollThread = nil
    }

    func reset() {
        do_reset()
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
        url.withUnsafeFileSystemRepresentation { ptr -> Bool in
            guard let ptr else { return false }
            return read_bin_file(UnsafeMutablePointer(mutating: ptr)) == 1
        }
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
