import CEmu
import Foundation

/// Thread-safe replacement for the old JNI `queuedCodes` callback: C calls
/// `host_wait_event()`/`host_pause_event()` directly (declared `extern` in
/// the vendored `x48.c`/`actions.c`), instead of calling back into Java.
final class HostKeyQueue {
    static let shared = HostKeyQueue()

    private var codes: [Int32] = []
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)

    /// Matches HPView.key(): down -> code+1, up -> code+100.
    func pressKey(_ code: Int32, down: Bool) {
        lock.lock()
        codes.append(down ? code + 1 : code + 100)
        lock.unlock()
        semaphore.signal()
    }

    /// Called from C via host_wait_event(). Returns 0 if nothing is queued
    /// (matches the Java side's `if (queuedCodes.size()==0) return 0;`).
    func popCode() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return codes.isEmpty ? 0 : codes.removeFirst()
    }

    /// Called from C via host_pause_event(). Blocks until a key event
    /// arrives or a short timeout elapses, so the emulator's own timer
    /// ticks (battery check, clock) still advance while idle -- the
    /// original UNIX x48 did this with a 20ms SIGALRM; the Android port's
    /// pure JNI `Object.wait()` (no timeout) relied solely on key-press
    /// wakeups, which a no-op/untimed wait reproduces as a busy spin here.
    func waitForEventOrTimeout() {
        _ = semaphore.wait(timeout: .now() + 0.02)
    }
}

@_cdecl("host_wait_event")
func host_wait_event() -> Int32 {
    HostKeyQueue.shared.popCode()
}

@_cdecl("host_pause_event")
func host_pause_event() {
    HostKeyQueue.shared.waitForEventOrTimeout()
}
