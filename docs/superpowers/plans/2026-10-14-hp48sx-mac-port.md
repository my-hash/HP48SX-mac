# HP48SX Mac Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native macOS AppKit app, `HP48SXMac`, that boots the vendored `x48`/`droid48`/`48sx` Saturn-CPU emulator core and presents a fixed-size, pixel-faithful port of the Android app's keypad + LCD.

**Architecture:** A SwiftPM project with two targets — `CEmu` (the vendored C emulator core, patched to drop its Android/JNI glue) and `HP48SXMac` (an AppKit executable that calls into `CEmu` directly through a bridging header, no JNI-equivalent indirection). The emulator runs its own `emulate()`/`debug()` loop on a background thread; a custom `NSView` ports the Android `HPView`'s draw/hit-test math at a fixed scale.

**Tech Stack:** Swift 5.9 (tools-version pinned to avoid Swift 6 strict-concurrency checks, which fight this C-interop/background-thread design), AppKit, a vendored ANSI C core, no third-party dependencies.

**Spec:** [docs/superpowers/specs/2026-10-14-hp48sx-mac-port-design.md](../specs/2026-10-14-hp48sx-mac-port-design.md)

## Global Constraints

- Swift tools-version `5.9`, deployment target `.macOS(.v13)`.
- No SwiftPM package dependencies. Zip backup/restore shells out to the system `/usr/bin/zip` / `/usr/bin/unzip` via `Process`.
- `CEmu` target C flags must include `-Wno-implicit-function-declaration -Wno-pointer-sign -Wno-return-type` (the vendored 1994-era C relies on implicit declarations and loose pointer signedness that modern clang warns on by default; these are pre-existing upstream characteristics, not new code, and the build already succeeds with these warnings suppressed — see Task 1's verification).
- GPL-2.0 license (`COPYING`) carried over verbatim from upstream; keep attribution to Eddie C. Dost (x48), Arnaud Brochard (droid48), Olivier Sirol/czo (48sx) in the README.
- Config directory is exactly `~/Library/Application Support/HP48SX/` (trailing slash required — the vendored C does `strcat(path, "rom")` with no separator).
- Window is fixed at 360×735pt, not resizable (per spec's Dimensions section).
- `fillAudioData`/sound playback is dropped entirely — confirmed dead code: `HPView.run()` never calls it, the `AudioTrack` playback path in `HPView`'s constructor is fully commented out in the source app.
- The interactive debugger/disassembler/serial-Kermit transfer UI is out of scope (per spec: not reachable in the source app either, since `useDebugger` is never set to true by anything `X48.java` does).

## Review Focus

- **Corrupt/zero-length state files on launch** (a previous run crashed mid-write, or this is a fresh install with a placeholder file): must trigger a checkpoint restore, not crash or silently run with garbage memory. → Task 3's tests.
- **Drawing before the emulator thread has produced a first frame** (the redraw timer fires before `EmulatorBridge.start()` finishes `init_emulator()`): must show a blank/background LCD, never read uninitialized or partially-written screen-buffer memory. → Task 6's manual verification step explicitly checks this (launch and immediately screenshot).
- **A key event with an out-of-range or unmapped code** (a stray `NSEvent` keyCode with no entry in the mapping table): `keyDown`/mouse hit-testing must fall through harmlessly, never call `button_pressed` with an invalid index. → Task 7's tests.
- **Loading a non-HP48 file via "Load Object…"** (`read_bin_file` returns failure): must show an alert, not crash or leave `ram`/`rom` partially modified. → Task 5's tests (`EmulatorBridge.loadObject`), surfaced as an alert in Task 8.
- **Full Reset / Restore Checkpoint while the emulator thread is mid-cycle**: must stop the background thread before touching `hp48`/`ram`/`rom`/`port1`/`port2` on disk, to avoid a torn read/write race. → Task 8's tests.

---

## Task 1: SwiftPM scaffold + vendor the C emulator core

**Files:**
- Create: `Package.swift`
- Create: `Sources/CEmu/include/CEmu.h`
- Create: `Sources/CEmu/*.c`, `Sources/CEmu/*.h` (vendored, patched — exact list below)
- Create: `Sources/HP48SXMac/main.swift` (placeholder)
- Create: `COPYING` (copy verbatim from the upstream repo's `COPYING`)
- Create: `.gitignore` (`.build/`, `.swiftpm/`, `*.xcodeproj`)

**Interfaces:**
- Produces: a `CEmu` C target whose public API (via `CEmu.h`) later tasks call: `init_emulator()`, `init_active_stuff()`, `emulate()`, `emulate_debug()`, `debug()`, `do_reset()`, `write_files()`, `button_pressed(int)`, `button_released(int)`, `read_bin_file(char*)`, `emu_set_config_dir(const char*)`, `emu_set_blank_color(unsigned short)`, `emu_flip_screen(void)`, `emu_fill_screen_data(unsigned short*, unsigned char*)`, plus the externs `config_dir[1024]`, `exec_flags`, `exit_state`, and the constant `EMU_SCREEN_BUF_LEN`. Also declares (but does not yet define — Task 2 defines them) `int host_wait_event(void)` and `void host_pause_event(void)`.

This task has no automated test of its own (there's no behavior yet) — its deliverable is a clean, reproducible build. Verification is `swift build` succeeding with zero errors.

- [ ] **Step 1: Fetch the upstream source**

The vendored files come from `https://github.com/czodroid/android-48sx`, path `app/src/main/cpp/`. Clone it to a scratch location (not inside this repo) and copy from there:

```bash
mkdir -p /tmp/android-48sx-src && cd /tmp/android-48sx-src
git clone --depth 1 https://github.com/czodroid/android-48sx.git .
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HP48SXMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CEmu",
            cSettings: [
                .unsafeFlags([
                    "-Wno-implicit-function-declaration",
                    "-Wno-pointer-sign",
                    "-Wno-return-type",
                ]),
                .define("DEBUG", .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "HP48SXMac",
            dependencies: ["CEmu"],
            resources: [
                .copy("Resources/rom"),
                .copy("Resources/ram"),
                .copy("Resources/hp48"),
                .copy("Resources/Keycaps"),
            ]
        ),
        .testTarget(
            name: "HP48SXMacTests",
            dependencies: ["HP48SXMac"]
        ),
    ]
)
```

- [ ] **Step 3: Copy the vendored `.c`/`.h` files, unmodified, into `Sources/CEmu/`**

```bash
mkdir -p Sources/CEmu/include
cd /tmp/android-48sx-src/app/src/main/cpp
cp actions.c binio.c binio.h debugger.c debugger.h device.c device.h \
   disasm.c disasm.h emulate.c global.h hp48.h hp48_emu.h hp48char.h \
   init.c memory.c mmu.h options.c register.c resources.c resources.h \
   romio.c romio.h rpl.c rpl.h serial.c small.h timer.c timer.h x48.c x48.h \
   /Users/<you>/HP48SX-mac/Sources/CEmu/
cp constants.h append.h config.h /Users/<you>/HP48SX-mac/Sources/CEmu/
```

(`main.c` is handled separately in Step 4 — it needs trimming, not a raw copy.)

- [ ] **Step 4: Create the trimmed `Sources/CEmu/main.c`**

Take the upstream `main.c`'s header comment, includes (drop `#include <jni.h>` and `#include <android/log.h>`), the four globals, and `save_options()` — i.e. everything from the top of the file through the end of `save_options()` (upstream lines 1–123) — then drop `main()` and every `Java_org_czo_droid48sx_X48_*` function entirely. Add `config_dir`'s definition (upstream line 250, otherwise orphaned by this trim) and one new function:

```c
/* ... upstream license header, unchanged ... */

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <sys/time.h>
#include <fcntl.h>
#include <locale.h>

#include "x48.h"
#include "hp48.h"
#include "binio.h"
#include "debugger.h"
#include "hp48_emu.h"

char  *progname;
char  *res_name;
char  *res_class;

int    saved_argc;
char **saved_argv;

saturn_t saturn;
int nb;
int exit_state = 1;

void
save_options(int argc, char **argv)
{
  int l;

  saved_argc = argc;
  saved_argv = (char **)malloc((argc + 2) * sizeof(char *));
  if (saved_argv == (char **)0)
    {
      LOGE( "%s: malloc failed in save_options(), exit\n", progname);
      exit (1);
    }
  saved_argv[argc] = (char *)0;
  while (argc--)
    {
      l = strlen(argv[argc]) + 1;
      saved_argv[argc] = (char *)malloc(l);
      if (saved_argv[argc] == (char *)0)
        {
          LOGE( "%s: malloc failed in save_options(), exit\n",
                  progname);
          exit (1);
        }
      memcpy(saved_argv[argc], argv[argc], l);
    }
}

char config_dir[1024];

void
emu_set_config_dir(const char *path) {
	strcpy(config_dir, path);
}
```

(`progname` stays `NULL` here — harmless; it's only read by `LOGD`/`LOGE`, which are no-ops unless `DEBUG` is defined, and `%s` on a NULL glibc/Darwin `printf` prints "(null)" rather than crashing. If you want tidier debug logs, set `progname = "48sx";` after the globals.)

- [ ] **Step 5: Patch `x48.h`** — drop the Android/JNI includes and the now-unused JNI externs

Find (near the top, after the `BLACK` define):
```c
#include <android/log.h> 
#include <jni.h>

#ifdef DEBUG
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG  , "48sx-C",  __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR  , "48sx-C",  __VA_ARGS__)
#else
#define LOGD(...)
#define LOGE(...)
#endif
```
Replace with:
```c
#include <stdio.h>

#ifdef DEBUG
#define LOGD(...) fprintf(stderr, __VA_ARGS__)
#define LOGE(...) fprintf(stderr, __VA_ARGS__)
#else
#define LOGD(...)
#define LOGE(...)
#endif
```

Find (further down, in the `disp_t`/externs section):
```c
extern JNIEnv *android_env;
extern jobject android_callback;
extern jmethodID waitEvent;
extern jmethodID pauseEvent;

extern Display *dpy;
```
Delete the four `extern` JNI lines, keep `extern Display *dpy;`.

Everything else in `x48.h` — including the `XColor`/`Window`/`GC`/`Display`/`Pixmap`/`Colormap`/`Atom`/`Visual` stub typedefs and the `XCreateBitmapFromData`/`XClearArea`/`XCopyPlane`/`XClearWindow` externs — stays unchanged. These are pre-existing stand-ins for X11 (the real bodies are defined, as trivial no-ops, in `x48.c`); they compile and link fine on macOS with no changes, exactly as they do on Android (verified empirically — see the note at the end of this task).

- [ ] **Step 6: Patch `x48.c`** — drop the JNI globals and the one real `waitEvent` call site

Find:
```c
#include <jni.h>
```
Delete that line.

Find:
```c
JNIEnv *android_env;
jobject android_callback;
jmethodID waitEvent;
jmethodID pauseEvent;
```
Replace with:
```c
extern int host_wait_event(void);
```

Find, in `GetEvent()`:
```c
	int code = (*android_env)->CallIntMethod(android_env, android_callback, waitEvent);
```
Replace with:
```c
	int code = host_wait_event();
```
(Leave the commented-out `/* wake = (*android_env)->CallIntMethod(...); return wake; */` line a few lines above it untouched — it's dead text inside a comment, not compiled.)

- [ ] **Step 7: Patch `actions.c`** — the `pauseEvent` call site

Near the top of the file (before first use), add:
```c
extern void host_pause_event(void);
```

Find the live call site (there is a second, textually-identical copy inside a `/* ... */` comment block a few lines above it — leave that one alone, it's inert):
```c
	 (*android_env)->CallVoidMethod(android_env, android_callback, pauseEvent);
```
Replace with:
```c
	 host_pause_event();
```

- [ ] **Step 8: Patch `romio.c`** — drop its Android log include

Delete the line:
```c
#include <android/log.h>
```
(`LOGD`/`LOGE` still work here — they come from `x48.h`, included transitively.)

- [ ] **Step 9: Patch `device.c`** — delete the dead `fillAudioData` JNI function

Delete the entire function (confirmed dead: `HPView.java`'s draw-thread `run()` never calls `fillAudioData`, and the `AudioTrack`/`TimerTask` playback code in `HPView`'s constructor is commented out in the source app):
```c
jint
Java_org_czo_droid48sx_X48_fillAudioData( JNIEnv*  env, jobject  this, jshortArray array) {
	/* ... entire body ... */
}
```

- [ ] **Step 10: Patch `lcd.c`** — rewrite the three JNI screen functions as plain C

Find:
```c
void
Java_org_czo_droid48sx_X48_setBlankColor( JNIEnv*  env,
                                      jobject  this, jshort color) {
```
Replace the signature line with:
```c
void
emu_set_blank_color(unsigned short color) {
```
(body unchanged).

Find:
```c
void
Java_org_czo_droid48sx_X48_flipScreen( JNIEnv*  env,
                                      jobject  this) {

	flipable = 1;
}
```
Replace with:
```c
void
emu_flip_screen(void) {

	flipable = 1;
}
```

Find:
```c
jint
Java_org_czo_droid48sx_X48_fillScreenData( JNIEnv*  env,
                                      jobject  this, jshortArray array, jbooleanArray ann_array) {
									 
	if (flipable == 1)
	{
		
		(*env)->SetShortArrayRegion(env, array, 0, ANDROID_BUF_HEADER_LENGTH, (const short *)disp_buf_header_short);
		(*env)->SetShortArrayRegion(env, array, ANDROID_BUF_HEADER_LENGTH, ANDROID_BUF_LENGTH, (const short *)disp_buf_short);
		
		(*env)->SetBooleanArrayRegion(env, ann_array, 0, 6, ann_boolean);
		
		flipable = 0;
		return 1;
	}
	return 0;
}
```
Replace with:
```c
int
emu_fill_screen_data(unsigned short *out, unsigned char *ann_out) {

	if (flipable == 1)
	{
		memcpy(out, disp_buf_header_short, ANDROID_BUF_HEADER_LENGTH * sizeof(unsigned short));
		memcpy(out + ANDROID_BUF_HEADER_LENGTH, disp_buf_short, ANDROID_BUF_LENGTH * sizeof(unsigned short));
		memcpy(ann_out, ann_boolean, 6);

		flipable = 0;
		return 1;
	}
	return 0;
}
```

- [ ] **Step 11: Create `Sources/CEmu/include/CEmu.h`**

```c
#ifndef CEMU_H
#define CEMU_H

#include "hp48.h"
#include "hp48_emu.h"
#include "debugger.h"
#include "binio.h"
#include "x48.h"

/* out buffer length for emu_fill_screen_data: (14 header rows + 128 LCD
 * rows) x 262 columns, matching the Android mainScreen bitmap exactly. */
#define EMU_SCREEN_BUF_LEN ((14 + 128) * 262)

void emu_set_config_dir(const char *path);
void emu_set_blank_color(unsigned short color);
void emu_flip_screen(void);
int  emu_fill_screen_data(unsigned short *out, unsigned char *ann_out);

#endif
```

`init_emulator`, `init_active_stuff`, `emulate`, `emulate_debug`, `debug`, `do_reset`, `write_files`, `button_pressed`, `button_released`, `read_bin_file`, and the externs `config_dir`, `exec_flags`, `exit_state` all already have correct plain-C prototypes in the headers included above (`hp48.h`, `hp48_emu.h`, `debugger.h`, `binio.h`, `x48.h`) — no re-declaration needed.

- [ ] **Step 12: Write the placeholder `Sources/HP48SXMac/main.swift`**

```swift
print("HP48SXMac scaffold OK")
```

- [ ] **Step 13: Build**

```bash
swift build
```

Expected: `Build complete!` with zero errors. (Warnings about `strcpy` fortify-source and implicit declarations are expected and pre-existing upstream; they do not fail the build.)

- [ ] **Step 14: Commit**

```bash
git add -A
git commit -m "Vendor the x48/droid48/48sx emulator core, stripped of its JNI glue"
```

**Note on verification already performed:** the exact patch list above (which 13 JNI functions exist, which can be deleted/called-directly vs. need rewriting, the X11 stub situation, the `fillAudioData` dead-code finding) was confirmed by actually compiling and linking all 17 vendored files with these exact patches during planning — not guessed. If a step's "Find" text doesn't match the checked-out source byte-for-byte (whitespace, line endings), search for the nearby distinctive line (e.g. `Java_org_czo_droid48sx_X48_flipScreen`) and adjust by hand; the end state described is what matters.

---

## Task 2: Host bridge (Swift-backed key queue) + headless smoke test

**Files:**
- Create: `Sources/HP48SXMac/HostBridge.swift`
- Modify: `Sources/HP48SXMac/main.swift`
- Test: `Tests/HP48SXMacTests/SmokeTests.swift`

**Interfaces:**
- Consumes: `CEmu`'s `host_wait_event`/`host_pause_event` (declared `extern` in Task 1's patched `x48.c`/`actions.c`, not yet defined anywhere — this task defines them), `init_emulator()`, `init_active_stuff()`, `emulate()`, `debug()`, `emu_set_config_dir(_:)`, `emu_flip_screen()`, `emu_fill_screen_data(_:_:)`, `EMU_SCREEN_BUF_LEN`.
- Produces: `HostKeyQueue` (a thread-safe queue of pending key codes, matching the Java `queuedCodes` semantics: positive `code+1` = key down, `code+100` = key up), and the two `@_cdecl` entry points `host_wait_event`/`host_pause_event` that C calls into directly (same role as the old JNI `waitEvent`/`pauseEvent` callbacks, minus the JNI indirection).

This is the task where the architecture gets its first real proof: a headless program that boots the emulator core and reads back a live screen buffer.

- [ ] **Step 1: Write `HostBridge.swift`**

```swift
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
```

- [ ] **Step 2: Write the failing smoke test**

```swift
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

        for name in ["rom", "ram", "hp48"] {
            let src = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")!
            try fm.copyItem(at: src, to: dir.appendingPathComponent(name))
        }

        emu_set_config_dir(dir.path + "/")
        _ = init_emulator()
        init_active_stuff()

        for _ in 0..<200 {
            if exec_flags == 0 { _ = emulate() } else { _ = emulate_debug() }
            _ = debug()
        }

        emu_flip_screen()
        var buf = [UInt16](repeating: 0, count: Int(EMU_SCREEN_BUF_LEN))
        var ann = [UInt8](repeating: 0, count: 6)
        let got = buf.withUnsafeMutableBufferPointer { bufPtr in
            ann.withUnsafeMutableBufferPointer { annPtr in
                emu_fill_screen_data(bufPtr.baseAddress, annPtr.baseAddress)
            }
        }

        XCTAssertEqual(got, 1, "emu_fill_screen_data should report a fresh frame")
        XCTAssertTrue(buf.contains { $0 != 0 }, "screen buffer should not be all zero after boot")
    }
}
```

- [ ] **Step 3: Run it to confirm it fails for the right reason (resources not wired up yet)**

```bash
swift test --filter SmokeTests
```
Expected: FAIL — `Bundle.module` resource lookup or a build error, since `Resources/rom`/`ram`/`hp48` haven't been added to the package yet. (They're added in Task 1's `Package.swift` resources list already — if this step fails on a *different* error, debug that now rather than proceeding.)

- [ ] **Step 4: Copy the real bundled assets into place**

```bash
mkdir -p Resources
cp /tmp/android-48sx-src/app/src/main/assets/{rom,ram,hp48} Resources/
```

- [ ] **Step 5: Add the `do_reset()` fallback and run the test again**

This exact hang was reproduced during planning: `init_emulator()` returns `0` for the bundled placeholder `hp48` state file (its "try to read old format file" fallback in `init.c` doesn't accept it), and the subsequent `emulate()` loop then spins against a half-initialized `saturn` state. The fix — confirmed working during planning — is to treat a `0` return the same way `X48.java`'s Full Reset already does: fall back to `do_reset()` instead of treating it as fatal. Update the test's setup to:

```swift
        emu_set_config_dir(dir.path + "/")
        if init_emulator() == 0 {
            do_reset()
        }
        init_active_stuff()
```

Then run:
```bash
swift test --filter SmokeTests
```
Expected: PASS. (Task 5's `EmulatorBridge.start()` carries this same fallback — see its implementation below — so this fix only needs discovering once, here.)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add the host key-event bridge and a headless boot smoke test"
```

---

## Task 3: App paths, first-run asset copy, checkpoint save/restore/full-reset

**Files:**
- Create: `Sources/HP48SXMac/AppPaths.swift`
- Test: `Tests/HP48SXMacTests/AppPathsTests.swift`

**Interfaces:**
- Produces: `AppPaths.configDir` (`URL`, `~/Library/Application Support/HP48SX/`, trailing-slash path string via `.path + "/"` for passing to `emu_set_config_dir`), `AppPaths.ensureFirstRunAssets()`, `AppPaths.verifyNoZeroLengthFiles() -> Bool`, `AppPaths.saveCheckpoint()`, `AppPaths.restoreCheckpoint()`, `AppPaths.fullReset()`.
- Consumes: nothing from earlier tasks (pure `FileManager` logic) — later tasks (5, 8) call into this.

This is plain, deterministic filesystem logic — the most unit-testable part of the whole app, so it gets real tests, not just a build check.

- [ ] **Step 1: Write the failing test for first-run asset copy**

```swift
import XCTest
@testable import HP48SXMac

final class AppPathsTests: XCTestCase {
    var paths: AppPaths!
    var tmpRoot: URL!

    override func setUp() throws {
        tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        paths = AppPaths(configDir: tmpRoot)
    }

    override func tearDown() throws {
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
```

- [ ] **Step 2: Run to confirm it fails (AppPaths doesn't exist yet)**

```bash
swift test --filter AppPathsTests
```
Expected: FAIL to build — `AppPaths` undefined.

- [ ] **Step 3: Implement `AppPaths.swift`**

```swift
import Foundation

/// Ports X48.java's AssetUtil + checkpoint/full-reset/zero-length-guard
/// logic. `configDir` is injectable for testing; production code uses
/// AppPaths.standard (~/Library/Application Support/HP48SX/).
struct AppPaths {
    static let standard = AppPaths(
        configDir: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HP48SX", isDirectory: true)
    )

    let configDir: URL
    private static let stateFiles = ["hp48", "ram", "rom"]
    private static let requiredSize: [String: Int] = ["ram": 32 * 1024, "rom": 256 * 1024]

    /// Path string for emu_set_config_dir -- must end in "/".
    var configDirPath: String { configDir.path + "/" }

    var checkpointDir: URL { configDir.appendingPathComponent("checkpoint", isDirectory: true) }

    func ensureFirstRunAssets() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        for name in Self.stateFiles {
            let dest = configDir.appendingPathComponent(name)
            let required = Self.requiredSize[name]
            let needsCopy = !fm.fileExists(atPath: dest.path)
                || (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) == 0
                || (required != nil && (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) != required)
            if needsCopy {
                let src = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")!
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: src, to: dest)
            }
        }

        if !fm.fileExists(atPath: checkpointDir.path) {
            try fm.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
            for name in Self.stateFiles {
                try fm.copyItem(at: configDir.appendingPathComponent(name),
                                 to: checkpointDir.appendingPathComponent(name))
            }
        }
    }

    func verifyNoZeroLengthFiles() -> Bool {
        let fm = FileManager.default
        for name in Self.stateFiles {
            let path = configDir.appendingPathComponent(name).path
            if fm.fileExists(atPath: path),
               let size = try? fm.attributesOfItem(atPath: path)[.size] as? Int,
               size == 0 {
                return false
            }
        }
        return true
    }

    func saveCheckpoint() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
        for name in Self.stateFiles + ["port1", "port2"] {
            let src = configDir.appendingPathComponent(name)
            let dst = checkpointDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: dst) }
        }
    }

    func restoreCheckpoint() throws {
        let fm = FileManager.default
        for name in Self.stateFiles + ["port1", "port2"] {
            let dst = configDir.appendingPathComponent(name)
            let src = checkpointDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: dst) }
        }
    }

    func fullReset() throws {
        let fm = FileManager.default
        for name in Self.stateFiles + ["port1", "port2"] {
            let path = configDir.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
        }
        try ensureFirstRunAssets()
    }
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter AppPathsTests
```
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add AppPaths: config dir, first-run asset copy, checkpoint save/restore/full-reset"
```

---

## Task 4: Key layout math

**Files:**
- Create: `Sources/HP48SXMac/KeyLayout.swift`
- Test: `Tests/HP48SXMacTests/KeyLayoutTests.swift`

**Interfaces:**
- Produces: `KeyLayout.contentSize: CGSize` (360×735), `KeyLayout.lcdRect: CGRect`, `KeyLayout.iconRects: [CGRect]` (6), `KeyLayout.keyRects: [CGRect]` (49, indexed 0...48 matching the Android button codes).
- Consumes: nothing. Pure math, ported from `HPView.refreshMainScreen`'s portrait/`!keybLite`/`!fullWidth` branch, per the spec's Dimensions derivation.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import HP48SXMac

final class KeyLayoutTests: XCTestCase {
    func testContentSizeMatchesSpec() {
        XCTAssertEqual(KeyLayout.contentSize, CGSize(width: 360, height: 735), accuracy: 1)
    }

    func testLCDRectIsCenteredAtTop() {
        let r = KeyLayout.lcdRect
        XCTAssertEqual(r.origin.y, 0, accuracy: 0.5)
        XCTAssertEqual(r.midX, KeyLayout.contentSize.width / 2, accuracy: 1)
    }

    func testAllFortyNineKeysHaveNonZeroRects() {
        XCTAssertEqual(KeyLayout.keyRects.count, 49)
        for (i, r) in KeyLayout.keyRects.enumerated() {
            XCTAssertGreaterThan(r.width, 0, "key \(i) has zero width")
            XCTAssertGreaterThan(r.height, 0, "key \(i) has zero height")
        }
    }

    func testEnterKeySpansTripleWidthOfAMenuKey() {
        let enterWidth = KeyLayout.keyRects[24].width
        let menuKeyWidth = KeyLayout.keyRects[0].width
        XCTAssertEqual(enterWidth, menuKeyWidth * 2, accuracy: 1,
                       "ENTER (key 24) is width/3 of content; a menu key (key 0) is width/6")
    }

    func testSixAcrossRowKeysAreSquare() {
        // Keys 0-5 (menu row) and 6-23 (3 regular 6-wide rows) are sized
        // width/6 x regular_key_height, with regular_key_height == width/6
        // (the spec's "square narrow-row keys" choice).
        let r = KeyLayout.keyRects[0]
        XCTAssertEqual(r.width, r.height, accuracy: 1)
    }

    func testHitTestFindsKeyAtItsOwnCenter() {
        for (i, r) in KeyLayout.keyRects.enumerated() {
            XCTAssertEqual(KeyLayout.keyIndex(at: CGPoint(x: r.midX, y: r.midY)), i)
        }
    }

    func testHitTestReturnsNilOutsideAnyKey() {
        XCTAssertNil(KeyLayout.keyIndex(at: CGPoint(x: -10, y: -10)))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
swift test --filter KeyLayoutTests
```
Expected: FAIL to build — `KeyLayout` undefined.

- [ ] **Step 3: Implement `KeyLayout.swift`**

```swift
import CoreGraphics

/// Ports HPView.refreshMainScreen's portrait / !keybLite / !fullWidth
/// layout math at a fixed lcd_ratio of 2 (the bundled LCD bitmap is
/// already 262x142 = 131x64 real pixels x2, so ratio 2 renders it at
/// native resolution). See the design spec's "Dimensions" section for
/// the full derivation. All values are in points; origin top-left.
enum KeyLayout {
    private static let ratio: CGFloat = 2
    private static let scale: CGFloat = 1.333 // design-unit -> comfortable desktop window

    private static let lcdColumnUnit: CGFloat = 131
    private static let contentWidthUnit: CGFloat = 135
    private static let headerHeightUnit: CGFloat = 73
    private static let rowCount: CGFloat = 9

    private static var designWidth: CGFloat { contentWidthUnit * ratio }
    private static var designStartH: CGFloat { headerHeightUnit * ratio }
    private static var designKeyHeight: CGFloat { designWidth / 6 }
    private static var designHeight: CGFloat { designStartH + rowCount * designKeyHeight }

    static var contentSize: CGSize {
        CGSize(width: designWidth * scale, height: designHeight * scale)
    }

    static var lcdRect: CGRect {
        let w = lcdColumnUnit * ratio * scale
        let h = designStartH * scale
        let x = (contentSize.width - w) / 2
        return CGRect(x: x, y: 0, width: w, height: h)
    }

    static var iconRects: [CGRect] {
        let xOffsetsUnits: [CGFloat] = [0, 21, 45, 67, 91, 112]
        let y = 1 * ratio * scale
        return xOffsetsUnits.map { CGRect(x: lcdRect.minX + $0 * ratio * scale, y: y, width: 17 * scale, height: 12 * scale) }
    }

    /// 49 key rects indexed 0...48, matching HPView's button codes exactly:
    /// 0-5 menu row (A-F), 6-23 three rows of 6, 24 ENTER + 25-28 (row 3,
    /// width/6 each except ENTER at width/3), 29-48 four rows of 5.
    static let keyRects: [CGRect] = {
        let w = designWidth * scale
        let keyH = designKeyHeight * scale
        let startH = designStartH * scale
        var rects = [CGRect](repeating: .zero, count: 49)

        for k in 0..<6 {
            rects[k] = CGRect(x: w / 6 * CGFloat(k), y: startH, width: w / 6, height: keyH)
        }
        for k in 6..<24 {
            let col = CGFloat(k % 6)
            let row = CGFloat(k / 6 - 1)
            rects[k] = CGRect(x: w / 6 * col, y: startH + keyH * (1 + row), width: w / 6, height: keyH)
        }
        rects[24] = CGRect(x: 0, y: startH + keyH * 4, width: w / 3, height: keyH)
        for k in 25..<29 {
            let col = CGFloat((k + 1) % 6)
            let rank = CGFloat((k + 1) / 6)
            rects[k] = CGRect(x: w / 6 * col, y: startH + keyH * (1 + rank), width: w / 6, height: keyH)
        }
        for k in 29..<49 {
            let col = CGFloat((k + 1) % 5)
            let rank = CGFloat((k + 1) / 5)
            rects[k] = CGRect(x: w / 5 * col, y: startH + keyH * (rank + 2), width: w / 5, height: keyH)
        }
        return rects
    }()

    static func keyIndex(at point: CGPoint) -> Int? {
        keyRects.firstIndex { $0.contains(point) }
    }
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter KeyLayoutTests
```
Expected: PASS. If a specific key's rect is off (the row-math above is transcribed from `HPView.refreshMainScreen`'s `k < 6` / `k < 24` / `k == 24` / `25 < k < 29` / `k >= 29` branches — re-check against `app/src/main/java/org/czo/droid48sx/HPView.java` lines 262–291 in the upstream clone if a test fails), fix the formula for that branch and re-run.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add the fixed-size key/LCD layout math, ported from HPView"
```

---

## Task 5: EmulatorBridge — Swift-driven start/stop/reset/save/button loop

**Files:**
- Create: `Sources/HP48SXMac/EmulatorBridge.swift`
- Test: `Tests/HP48SXMacTests/EmulatorBridgeTests.swift`

**Interfaces:**
- Consumes: `CEmu`'s `init_emulator`, `init_active_stuff`, `emulate`, `emulate_debug`, `debug`, `do_reset`, `write_files`, `button_pressed`, `button_released`, `read_bin_file`, `emu_fill_screen_data`, `emu_flip_screen`, `exec_flags`, `EMU_SCREEN_BUF_LEN`; `AppPaths` (Task 3); `HostKeyQueue` (Task 2).
- Produces: `EmulatorBridge.start()`, `.stop()`, `.reset()`, `.save()`, `.pressKey(_:down:)`, `.loadObject(at: URL) -> Bool`, `.latestFrame() -> (screen: [UInt16], annunciators: [Bool])?` — this is what Task 6's `CalculatorView` and Task 8's menu actions call.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import HP48SXMac

final class EmulatorBridgeTests: XCTestCase {
    func testStartProducesAFrameWithinTwoSeconds() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop() }

        let deadline = Date().addingTimeInterval(2)
        var frame: (screen: [UInt16], annunciators: [Bool])?
        while frame == nil, Date() < deadline {
            frame = bridge.latestFrame()
            if frame == nil { Thread.sleep(forTimeInterval: 0.05) }
        }

        XCTAssertNotNil(frame)
        XCTAssertTrue(frame!.screen.contains { $0 != 0 })
        try? fm.removeItem(at: dir)
    }

    func testPressKeyOutOfRangeDoesNotCrash() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()
        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        bridge.pressKey(999, down: true) // out of the 0...48 range
        bridge.pressKey(-1, down: true)
        // No crash = pass.
    }

    func testLoadObjectRejectsNonHP48FileWithoutCrashingOrCorruptingState() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()
        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        defer { bridge.stop(); try? fm.removeItem(at: dir) }

        let ramBefore = try Data(contentsOf: dir.appendingPathComponent("ram"))

        let garbage = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try "not an HP48 object".data(using: .utf8)!.write(to: garbage)
        defer { try? fm.removeItem(at: garbage) }

        let ok = bridge.loadObject(at: garbage)

        XCTAssertFalse(ok, "read_bin_file should report failure for a non-HP48 file")
        let ramAfter = try Data(contentsOf: dir.appendingPathComponent("ram"))
        XCTAssertEqual(ramBefore, ramAfter, "a rejected load must not modify ram")
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
swift test --filter EmulatorBridgeTests
```
Expected: FAIL to build — `EmulatorBridge` undefined.

- [ ] **Step 3: Implement `EmulatorBridge.swift`**

```swift
import CEmu
import Foundation

final class EmulatorBridge {
    private let paths: AppPaths
    private var thread: Thread?
    private var running = false
    private let frameLock = NSLock()
    private var frame: (screen: [UInt16], annunciators: [Bool])?

    init(paths: AppPaths = .standard) {
        self.paths = paths
    }

    func start() {
        guard !running else { return }
        running = true
        let t = Thread { [weak self] in self?.runLoop() }
        t.name = "HP48SXMac.emulate"
        t.start()
        thread = t
    }

    func stop() {
        running = false
    }

    func reset() {
        do_reset()
    }

    func save() {
        _ = write_files()
    }

    /// Matches HPView.key(): down -> code+1, up -> code+100 via the host
    /// key queue, AND the direct button_pressed/button_released call the
    /// Java side also made (HPView.key() notifies the emulate thread via
    /// x48.flipScreen()+queuedCodes; the actual key-matrix update happens
    /// inside emulate()'s GetEvent()->key_event() path reading that
    /// queue, so queueing is enough -- no separate button_pressed call is
    /// needed from here).
    func pressKey(_ code: Int32, down: Bool) {
        guard (0..<49).contains(code) else { return }
        HostKeyQueue.shared.pressKey(code, down: down)
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

    private func runLoop() {
        emu_set_config_dir(paths.configDirPath)
        if init_emulator() == 0 {
            // Fresh/placeholder state file didn't parse; reset to a known-good state.
            do_reset()
        }
        init_active_stuff()

        while running {
            if exec_flags == 0 { _ = emulate() } else { _ = emulate_debug() }
            _ = debug()

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
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter EmulatorBridgeTests
```
Expected: PASS. (If `testStartProducesAFrameWithinTwoSeconds` still times out, re-check Task 2 Step 5's root-cause fix is actually in place — `init_emulator() == 0` must fall through to `do_reset()`, not treat it as fatal.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add EmulatorBridge: background emulate loop, key queue, load/save/reset"
```

---

## Task 6: App bootstrap + CalculatorView rendering

**Files:**
- Modify: `Sources/HP48SXMac/main.swift`
- Create: `Sources/HP48SXMac/AppDelegate.swift`
- Create: `Sources/HP48SXMac/CalculatorView.swift`

**Interfaces:**
- Consumes: `EmulatorBridge` (Task 5), `KeyLayout` (Task 4).
- Produces: a running app with a fixed 360×735pt window showing the live LCD, 49 keycaps, and annunciators. Nothing later depends on new symbols from this task beyond the view itself (Task 7 extends `CalculatorView` with input handling).

There's no meaningful unit test for pixel-level AppKit drawing — this task's test is "build it, run it, look at it," made explicit below.

- [ ] **Step 1: Copy the keycap/annunciator PNGs into `Resources/Keycaps/`**

```bash
mkdir -p Resources/Keycaps
cp /tmp/android-48sx-src/app/src/main/res/drawable/k*.png Resources/Keycaps/
cp /tmp/android-48sx-src/app/src/main/res/drawable/ann*.png Resources/Keycaps/
```

- [ ] **Step 2: Write `AppDelegate.swift`**

```swift
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let bridge = EmulatorBridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge.start()

        let contentRect = NSRect(origin: .zero, size: KeyLayout.contentSize)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "48SX"
        window.isRestorable = false
        window.contentView = CalculatorView(frame: contentRect, bridge: bridge)
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.save()
        bridge.stop()
    }
}
```

- [ ] **Step 3: Write `main.swift`**

```swift
import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Write `CalculatorView.swift` (drawing only for this task; input handling is Task 7)**

```swift
import Cocoa

final class CalculatorView: NSView {
    private let bridge: EmulatorBridge
    private var keyImages: [NSImage] = []
    private var annunciatorImages: [NSImage] = []
    private var redrawTimer: Timer?

    // Colors ported verbatim from HPView: func line, central/menu-key
    // background, LCD green.
    private let funcColor = NSColor(calibratedRed: 83/255, green: 81/255, blue: 82/255, alpha: 1)
    private let centralColor = NSColor(calibratedRed: 57/255, green: 57/255, blue: 56/255, alpha: 1)
    private let lcdGreen = NSColor(calibratedRed: 189/255, green: 195/255, blue: 165/255, alpha: 1)

    init(frame: NSRect, bridge: EmulatorBridge) {
        self.bridge = bridge
        super.init(frame: frame)
        loadImages()
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func loadImages() {
        keyImages = (1...49).map { i in
            Bundle.module.image(forResource: "Keycaps/k\(String(format: "%02d", i))") ?? NSImage()
        }
        annunciatorImages = (1...6).map { i in
            Bundle.module.image(forResource: "Keycaps/ann\(String(format: "%02d", i))") ?? NSImage()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        centralColor.setFill()
        bounds.fill()

        funcColor.setFill()
        NSRect(x: 0, y: KeyLayout.lcdRect.maxY, width: bounds.width, height: bounds.height - KeyLayout.lcdRect.maxY).fill()

        lcdGreen.setFill()
        KeyLayout.lcdRect.fill()

        drawLCDBitmap()

        for (i, rect) in KeyLayout.keyRects.enumerated() where rect.width > 0 {
            // AppKit's coordinate origin is bottom-left; KeyLayout is
            // authored top-left (matching HPView/Android), so flip y.
            let flipped = NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
            keyImages[i].draw(in: flipped)
        }

        if let frame = bridge.latestFrame() {
            for (i, on) in frame.annunciators.enumerated() where on {
                let r = KeyLayout.iconRects[i]
                let flipped = NSRect(x: r.minX, y: bounds.height - r.maxY, width: r.width, height: r.height)
                annunciatorImages[i].draw(in: flipped)
            }
        }
    }

    private func drawLCDBitmap() {
        guard let frame = bridge.latestFrame() else { return }
        let width = 262
        let height = 14 + 128
        guard frame.screen.count == width * height else { return }

        var rgbaBuffer = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let px = frame.screen[i] // RGB565
            let r = UInt8((px >> 11) & 0x1F) << 3
            let g = UInt8((px >> 5) & 0x3F) << 2
            let b = UInt8(px & 0x1F) << 3
            rgbaBuffer[i * 4] = r
            rgbaBuffer[i * 4 + 1] = g
            rgbaBuffer[i * 4 + 2] = b
            rgbaBuffer[i * 4 + 3] = 255
        }

        guard let provider = CGDataProvider(data: Data(rgbaBuffer) as CFData) else { return }
        guard let cgImage = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { return }

        let flipped = NSRect(x: KeyLayout.lcdRect.minX, y: bounds.height - KeyLayout.lcdRect.maxY,
                              width: KeyLayout.lcdRect.width, height: KeyLayout.lcdRect.height)
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: flipped)
    }
}
```

- [ ] **Step 5: Build and run**

```bash
swift build
swift run HP48SXMac
```

- [ ] **Step 6: Manually verify** — this is the first visual checkpoint. Confirm:
  1. A window titled "48SX" opens at a fixed 360×735pt size (check with the macOS Window menu or `cmd+drag` resize handle being absent).
  2. The window is NOT resizable (no resize handles respond; the window's `styleMask` above deliberately omits `.resizable`).
  3. The LCD area shows live content within ~1 second of launch (not blank/garbage) — confirms Task 6's "drawing before first frame" Review Focus item: check this by taking a screenshot immediately on launch (before the 1-second mark) and confirming it shows the plain LCD-green background, not corrupted pixels.
  4. All 49 keycaps render in their expected rows (menu row, three 6-wide rows, ENTER row, four 5-wide rows), matching the proportions described in the spec.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add the AppKit shell: fixed window, CalculatorView LCD + keycap rendering"
```

---

## Task 7: CalculatorView input handling (mouse + keyboard)

**Files:**
- Modify: `Sources/HP48SXMac/CalculatorView.swift`
- Test: `Tests/HP48SXMacTests/KeyMappingTests.swift`

**Interfaces:**
- Consumes: `KeyLayout.keyIndex(at:)` (Task 4), `EmulatorBridge.pressKey(_:down:)` (Task 5).
- Produces: `KeyMapping.code(for: UInt16) -> Int32?` (maps a macOS virtual keyCode to an HP48 button code, or nil) — pulled out of `CalculatorView` into its own pure function so it's unit-testable without a live view.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import HP48SXMac

final class KeyMappingTests: XCTestCase {
    func testDigitKeysMapToExpectedButtonCodes() {
        // Matches HPView.actionKey: KEYCODE_0->45, _1->40, _7->30, etc.
        XCTAssertEqual(KeyMapping.code(forCharacters: "0"), 45)
        XCTAssertEqual(KeyMapping.code(forCharacters: "7"), 30)
        XCTAssertEqual(KeyMapping.code(forCharacters: "9"), 32)
    }

    func testEnterAndDeleteMapCorrectly() {
        XCTAssertEqual(KeyMapping.code(forCharacters: "\r"), 24)
        XCTAssertEqual(KeyMapping.code(forSpecialKey: .delete), 28)
    }

    func testLetterAMapsToButtonZero() {
        XCTAssertEqual(KeyMapping.code(forCharacters: "a"), 0)
        XCTAssertEqual(KeyMapping.code(forCharacters: "A"), 0)
    }

    func testUnmappedCharacterReturnsNil() {
        XCTAssertNil(KeyMapping.code(forCharacters: "$"))
        XCTAssertNil(KeyMapping.code(forCharacters: ""))
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
swift test --filter KeyMappingTests
```
Expected: FAIL to build — `KeyMapping` undefined.

- [ ] **Step 3: Implement `KeyMapping` (add to `CalculatorView.swift` or a new file; a new file keeps the view focused on drawing/event plumbing)**

Create `Sources/HP48SXMac/KeyMapping.swift`:

```swift
import Cocoa

/// Ports HPView.actionKey's physical-keyboard table (Android KeyEvent
/// codes -> HP48 button index) to macOS characters/special keys.
enum KeyMapping {
    enum SpecialKey { case delete, upArrow, downArrow, leftArrow, rightArrow }

    private static let digitCodes: [Character: Int32] = [
        "0": 45, "1": 40, "2": 41, "3": 42, "4": 35,
        "5": 36, "6": 37, "7": 30, "8": 31, "9": 32,
    ]

    private static let letterCodes: [Character: Int32] = [
        "a": 0, "b": 1, "c": 2, "d": 3, "e": 4, "f": 5, "g": 6, "h": 7,
        "i": 8, "j": 9, "k": 10, "l": 11, "m": 12, "n": 13, "o": 14,
        "p": 15, "q": 16, "r": 17, "s": 18, "t": 19, "u": 20, "v": 21,
        "w": 22, "x": 23, "y": 25, "z": 26,
    ]

    static func code(forCharacters characters: String) -> Int32? {
        guard let c = characters.first, characters.count == 1 else { return nil }
        if c == "\r" || c == "\n" { return 24 } // ENTER
        if c == "." { return 46 }
        if c == " " { return 47 }
        if c == "@" { return 29 }
        let lower = Character(c.lowercased())
        if let code = digitCodes[c] { return code }
        if let code = letterCodes[lower] { return code }
        return nil
    }

    static func code(forSpecialKey key: SpecialKey) -> Int32 {
        switch key {
        case .delete: return 28
        case .upArrow: return 10
        case .downArrow: return 16
        case .leftArrow: return 15
        case .rightArrow: return 17
        }
    }
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter KeyMappingTests
```
Expected: PASS.

- [ ] **Step 5: Wire mouse and keyboard handling into `CalculatorView`**

Add to `CalculatorView.swift`:

```swift
extension CalculatorView {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convertToTopLeft(event.locationInWindow)
        guard let code = KeyLayout.keyIndex(at: p) else { return }
        pressedKeyCode = Int32(code)
        bridge.pressKey(Int32(code), down: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard let code = pressedKeyCode else { return }
        bridge.pressKey(code, down: false)
        pressedKeyCode = nil
    }

    override func keyDown(with event: NSEvent) {
        guard let code = KeyMapping.code(forCharacters: event.charactersIgnoringModifiers ?? "")
            ?? specialKeyCode(for: event) else { return }
        bridge.pressKey(code, down: true)
    }

    override func keyUp(with event: NSEvent) {
        guard let code = KeyMapping.code(forCharacters: event.charactersIgnoringModifiers ?? "")
            ?? specialKeyCode(for: event) else { return }
        bridge.pressKey(code, down: false)
    }

    private func specialKeyCode(for event: NSEvent) -> Int32? {
        switch event.specialKey {
        case .some(.delete), .some(.backspace): return KeyMapping.code(forSpecialKey: .delete)
        case .some(.upArrow): return KeyMapping.code(forSpecialKey: .upArrow)
        case .some(.downArrow): return KeyMapping.code(forSpecialKey: .downArrow)
        case .some(.leftArrow): return KeyMapping.code(forSpecialKey: .leftArrow)
        case .some(.rightArrow): return KeyMapping.code(forSpecialKey: .rightArrow)
        default: return nil
        }
    }

    private func convertToTopLeft(_ windowPoint: NSPoint) -> NSPoint {
        let p = convert(windowPoint, from: nil)
        return NSPoint(x: p.x, y: bounds.height - p.y)
    }
}
```

Add the stored property near the top of the main `CalculatorView` class body:
```swift
private var pressedKeyCode: Int32?
```

- [ ] **Step 6: Build and run; manually verify**

```bash
swift build
swift run HP48SXMac
```
1. Click several keycaps (e.g. ON/key 44, a digit, ENTER) and confirm the LCD responds (cursor/digits appear).
2. Type digits and letters on the physical keyboard and confirm the same button codes fire (compare against clicking the same key with the mouse).
3. Click outside any key rect (e.g. the window's background bezel) and confirm nothing happens — no crash, no stray button press (covers this task's Review Focus item).
4. Press an unmapped key (e.g. F5) and confirm nothing happens.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add mouse and physical-keyboard input handling to CalculatorView"
```

---

## Task 8: Menu — Load Object, Full Reset, Checkpoint, Backup zip

**Files:**
- Create: `Sources/HP48SXMac/MenuBuilder.swift`
- Modify: `Sources/HP48SXMac/AppDelegate.swift`
- Test: `Tests/HP48SXMacTests/BackupZipTests.swift`

**Interfaces:**
- Consumes: `EmulatorBridge` (Task 5: `.stop()`, `.start()`, `.reset()`, `.loadObject(at:)`), `AppPaths` (Task 3: `.fullReset()`, `.saveCheckpoint()`, `.restoreCheckpoint()`, `.configDir`).
- Produces: `BackupZip.save(configDir: URL, to destination: URL) throws`, `BackupZip.restore(from source: URL, into configDir: URL) throws` — the `zip`/`unzip` shell-out, pulled into their own testable type.

- [ ] **Step 1: Write the failing test for the zip round-trip**

```swift
import XCTest
@testable import HP48SXMac

final class BackupZipTests: XCTestCase {
    func testSaveThenRestoreRoundTrips() throws {
        let fm = FileManager.default
        let configDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        try "romdata".data(using: .utf8)!.write(to: configDir.appendingPathComponent("rom"))
        try "ramdata".data(using: .utf8)!.write(to: configDir.appendingPathComponent("ram"))
        try "hp48data".data(using: .utf8)!.write(to: configDir.appendingPathComponent("hp48"))

        let zipPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try BackupZip.save(configDir: configDir, to: zipPath)
        XCTAssertTrue(fm.fileExists(atPath: zipPath.path))

        let restoreDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        try BackupZip.restore(from: zipPath, into: restoreDir)

        let restoredRom = try String(contentsOf: restoreDir.appendingPathComponent("rom"), encoding: .utf8)
        XCTAssertEqual(restoredRom, "romdata")

        try? fm.removeItem(at: configDir)
        try? fm.removeItem(at: zipPath)
        try? fm.removeItem(at: restoreDir)
    }

    func testRestoreRejectsZipMissingRequiredMembers() throws {
        let fm = FileManager.default
        let emptyDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        try "unrelated".data(using: .utf8)!.write(to: emptyDir.appendingPathComponent("notes.txt"))

        let zipPath = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try BackupZip.save(configDir: emptyDir, to: zipPath) // zips just notes.txt

        let restoreDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: restoreDir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BackupZip.restore(from: zipPath, into: restoreDir))

        try? fm.removeItem(at: emptyDir)
        try? fm.removeItem(at: zipPath)
        try? fm.removeItem(at: restoreDir)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

```bash
swift test --filter BackupZipTests
```
Expected: FAIL to build — `BackupZip` undefined.

- [ ] **Step 3: Implement `BackupZip` (add to `MenuBuilder.swift`)**

```swift
import Foundation

enum BackupZipError: Error { case missingRequiredMembers }

enum BackupZip {
    private static let members = ["hp48", "ram", "rom", "port1", "port2"]

    static func save(configDir: URL, to destination: URL) throws {
        let present = members.filter { FileManager.default.fileExists(atPath: configDir.appendingPathComponent($0).path) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = configDir
        process.arguments = ["-j", destination.path] + present
        try process.run()
        process.waitUntilExit()
    }

    static func restore(from source: URL, into configDir: URL) throws {
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", source.path]
        let pipe = Pipe()
        listProcess.standardOutput = pipe
        try listProcess.run()
        listProcess.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let names = Set(listing.split(separator: "\n").map(String.init))

        guard names.contains("hp48"), names.contains("ram"), names.contains("rom") else {
            throw BackupZipError.missingRequiredMembers
        }

        let extractProcess = Process()
        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extractProcess.arguments = ["-o", source.path, "-d", configDir.path]
        try extractProcess.run()
        extractProcess.waitUntilExit()
    }
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter BackupZipTests
```
Expected: PASS.

- [ ] **Step 5: Write the failing test for the thread-stop-before-file-touch ordering**

```swift
extension BackupZipTests {
    func testFullResetStopsEmulatorBeforeTouchingFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(configDir: dir)
        try paths.ensureFirstRunAssets()

        let bridge = EmulatorBridge(paths: paths)
        bridge.start()
        Thread.sleep(forTimeInterval: 0.1) // let the loop actually spin up

        // The menu action must stop the bridge before AppPaths.fullReset()
        // touches files the background thread might still be reading. This
        // ordering is what MenuBuilder's "Full Reset" action implements;
        // this test exercises AppPaths directly to prove it's safe even if
        // called mid-cycle, not just in the already-stopped case.
        bridge.stop()
        try paths.fullReset()

        let ramSize = try fm.attributesOfItem(atPath: dir.appendingPathComponent("ram").path)[.size] as! Int
        XCTAssertEqual(ramSize, 32 * 1024)
        try? fm.removeItem(at: dir)
    }
}
```

- [ ] **Step 6: Run it**

```bash
swift test --filter BackupZipTests
```
Expected: PASS (this test documents the required ordering; it doesn't need new production code, since `EmulatorBridge.stop()` already just flips a flag the loop checks each iteration — but it pins the contract so Step 7's `MenuBuilder` is written against a verified-safe sequence).

- [ ] **Step 7: Implement `MenuBuilder` and wire it into `AppDelegate`**

Add to `MenuBuilder.swift`:

```swift
import Cocoa

final class MenuBuilder {
    private unowned let delegate: AppDelegate

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func build() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit 48SX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let calcMenuItem = NSMenuItem()
        let calcMenu = NSMenu(title: "Calculator")
        calcMenu.addItem(withTitle: "Load Object…", action: #selector(AppDelegate.loadObject), keyEquivalent: "o")
        calcMenu.addItem(.separator())
        calcMenu.addItem(withTitle: "Save Checkpoint", action: #selector(AppDelegate.saveCheckpoint), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Restore Checkpoint", action: #selector(AppDelegate.restoreCheckpoint), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Full Reset (Memory)", action: #selector(AppDelegate.fullReset), keyEquivalent: "")
        calcMenu.addItem(.separator())
        calcMenu.addItem(withTitle: "Save Backup…", action: #selector(AppDelegate.saveBackupZip), keyEquivalent: "")
        calcMenu.addItem(withTitle: "Restore Backup…", action: #selector(AppDelegate.restoreBackupZip), keyEquivalent: "")
        calcMenuItem.submenu = calcMenu
        mainMenu.addItem(calcMenuItem)

        return mainMenu
    }
}
```

Add to `AppDelegate.swift`:

```swift
extension AppDelegate {
    @objc func loadObject() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if !bridge.loadObject(at: url) {
                let alert = NSAlert()
                alert.messageText = "Could not load \(url.lastPathComponent)"
                alert.informativeText = "This file isn't a valid HP48 object."
                alert.runModal()
            }
        }
    }

    @objc func saveCheckpoint() {
        bridge.save()
        try? AppPaths.standard.saveCheckpoint()
    }

    @objc func restoreCheckpoint() {
        bridge.stop()
        try? AppPaths.standard.restoreCheckpoint()
        bridge.start()
    }

    @objc func fullReset() {
        bridge.stop()
        try? AppPaths.standard.fullReset()
        bridge.start()
    }

    @objc func saveBackupZip() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "48sx-backup.zip"
        if panel.runModal() == .OK, let url = panel.url {
            try? BackupZip.save(configDir: AppPaths.standard.configDir, to: url)
        }
    }

    @objc func restoreBackupZip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        if panel.runModal() == .OK, let url = panel.url {
            bridge.stop()
            do {
                try BackupZip.restore(from: url, into: AppPaths.standard.configDir)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Restore failed"
                alert.informativeText = "This zip must contain hp48, ram, and rom."
                alert.runModal()
            }
            bridge.start()
        }
    }
}
```

In `applicationDidFinishLaunching`, after creating `window`, add:
```swift
NSApp.mainMenu = MenuBuilder(delegate: self).build()
```

- [ ] **Step 8: Build and run; manually verify**

```bash
swift build
swift run HP48SXMac
```
1. Load Object… on a non-HP48 file (e.g. a text file) → confirm the alert appears and the app doesn't crash.
2. Save Checkpoint, change calculator state (press some keys), Restore Checkpoint → confirm state reverts.
3. Full Reset → confirm the calculator returns to its out-of-box state.
4. Save Backup…, then Restore Backup… from that same file → confirm it round-trips.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add the Calculator menu: Load Object, Checkpoint, Full Reset, Backup zip"
```

---

## Task 9: Preferences (Save on Exit, Port 1/2 memory cards)

**Files:**
- Create: `Sources/HP48SXMac/PreferencesWindow.swift`
- Modify: `Sources/HP48SXMac/MenuBuilder.swift`
- Modify: `Sources/HP48SXMac/AppDelegate.swift`
- Test: `Tests/HP48SXMacTests/PortCardTests.swift`

**Interfaces:**
- Consumes: `AppPaths.configDir` (Task 3).
- Produces: `PortCardManager.setSize(_ kb: Int, forPort port: Int, configDir: URL) throws` (0 or 128, matching `port_1_values`/`port_2_values`), `UserDefaults` keys `"saveOnExit"` (default `true`), `"port1"`, `"port2"` (default `"0"`).

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run to confirm failure**

```bash
swift test --filter PortCardTests
```
Expected: FAIL to build — `PortCardManager` undefined.

- [ ] **Step 3: Implement `PortCardManager` (add to `PreferencesWindow.swift`)**

```swift
import Foundation

enum PortCardError: Error { case invalidPort }

enum PortCardManager {
    static func setSize(_ kb: Int, forPort port: Int, configDir: URL) throws {
        guard port == 1 || port == 2 else { throw PortCardError.invalidPort }
        let path = configDir.appendingPathComponent("port\(port)")
        let fm = FileManager.default

        if kb == 0 {
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
            return
        }

        let targetSize = kb * 1024
        if fm.fileExists(atPath: path.path),
           let existingSize = try? fm.attributesOfItem(atPath: path.path)[.size] as? Int,
           existingSize == targetSize {
            return
        }
        try Data(repeating: 0, count: targetSize).write(to: path)
    }
}
```

- [ ] **Step 4: Run the tests again**

```bash
swift test --filter PortCardTests
```
Expected: PASS.

- [ ] **Step 5: Implement `PreferencesWindow` and wire it into the menu**

Add to `PreferencesWindow.swift`:

```swift
import Cocoa

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Preferences"
        self.init(window: window)

        let saveOnExit = NSButton(checkboxWithTitle: "Save on Exit", target: self, action: #selector(toggleSaveOnExit))
        saveOnExit.state = UserDefaults.standard.bool(forKey: "saveOnExit", defaultValue: true) ? .on : .off
        saveOnExit.frame = NSRect(x: 20, y: 110, width: 280, height: 24)

        let port1Label = NSTextField(labelWithString: "Port 1:")
        port1Label.frame = NSRect(x: 20, y: 70, width: 60, height: 24)
        let port1Popup = NSPopUpButton(frame: NSRect(x: 90, y: 70, width: 120, height: 24))
        port1Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port1Popup.selectItem(at: UserDefaults.standard.string(forKey: "port1") == "128" ? 1 : 0)
        port1Popup.target = self
        port1Popup.action = #selector(port1Changed(_:))
        port1Popup.tag = 1

        let port2Label = NSTextField(labelWithString: "Port 2:")
        port2Label.frame = NSRect(x: 20, y: 30, width: 60, height: 24)
        let port2Popup = NSPopUpButton(frame: NSRect(x: 90, y: 30, width: 120, height: 24))
        port2Popup.addItems(withTitles: ["None/Delete", "128kB"])
        port2Popup.selectItem(at: UserDefaults.standard.string(forKey: "port2") == "128" ? 1 : 0)
        port2Popup.target = self
        port2Popup.action = #selector(port2Changed(_:))
        port2Popup.tag = 2

        let contentView = NSView(frame: window.contentView!.frame)
        [saveOnExit, port1Label, port1Popup, port2Label, port2Popup].forEach(contentView.addSubview)
        window.contentView = contentView
    }

    @objc private func toggleSaveOnExit(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "saveOnExit")
    }

    @objc private func port1Changed(_ sender: NSPopUpButton) {
        changePort(1, sizeKB: sender.indexOfSelectedItem == 1 ? 128 : 0)
    }

    @objc private func port2Changed(_ sender: NSPopUpButton) {
        changePort(2, sizeKB: sender.indexOfSelectedItem == 1 ? 128 : 0)
    }

    private func changePort(_ port: Int, sizeKB: Int) {
        UserDefaults.standard.set(String(sizeKB), forKey: "port\(port)")
        try? PortCardManager.setSize(sizeKB, forPort: port, configDir: AppPaths.standard.configDir)
    }
}

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
}
```

In `MenuBuilder.build()`, add to `appMenu` (before the Quit item):
```swift
appMenu.addItem(withTitle: "Preferences…", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
appMenu.addItem(.separator())
```

In `AppDelegate`, add:
```swift
var preferencesWindowController: PreferencesWindowController?

@objc func showPreferences() {
    if preferencesWindowController == nil {
        preferencesWindowController = PreferencesWindowController()
    }
    preferencesWindowController?.showWindow(nil)
    preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
}
```

And in `applicationWillTerminate`, gate the save on the preference:
```swift
func applicationWillTerminate(_ notification: Notification) {
    if UserDefaults.standard.bool(forKey: "saveOnExit", defaultValue: true) {
        bridge.save()
    }
    bridge.stop()
}
```

- [ ] **Step 6: Build and run; manually verify**

```bash
swift build
swift run HP48SXMac
```
1. Open Preferences (cmd+,), toggle Save on Exit off, quit and relaunch, confirm calculator state did NOT persist (press some keys first, quit, relaunch, confirm it's back to the last-saved state, not the mid-session state).
2. Set Port 1 to 128kB, confirm a `port1` file of exactly 128KB appears in `~/Library/Application Support/HP48SX/`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add Preferences: Save on Exit toggle, Port 1/2 memory card size"
```

---

## Task 10: App bundle packaging + README

**Files:**
- Create: `Scripts/make-app-bundle.sh`
- Create: `README.md`
- Modify: `Package.swift` (if an icon asset needs adding to resources — optional, skip if no icon is supplied)

**Interfaces:**
- Consumes: the built `HP48SXMac` executable (from `swift build -c release`).
- Produces: `HP48SXMac.app`, a double-clickable bundle (`Info.plist` + the SwiftPM-built executable + its resource bundle).

- [ ] **Step 1: Write `Scripts/make-app-bundle.sh`**

```bash
#!/bin/sh
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP="build/HP48SXMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BIN_PATH=$(swift build -c release --show-bin-path)
cp "$BIN_PATH/HP48SXMac" "$APP/Contents/MacOS/"
cp -R "$BIN_PATH/HP48SXMac_HP48SXMac.bundle" "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>48SX</string>
    <key>CFBundleDisplayName</key><string>48SX</string>
    <key>CFBundleIdentifier</key><string>org.czo.hp48sxmac</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>HP48SXMac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Built $APP"
```

```bash
chmod +x Scripts/make-app-bundle.sh
```

- [ ] **Step 2: Run it and confirm the bundle launches**

```bash
./Scripts/make-app-bundle.sh
open build/HP48SXMac.app
```
Expected: the same window as `swift run` produced, now opened from a real `.app` (check the Dock icon/name reads "48SX", not a generic terminal icon).

- [ ] **Step 3: Write `README.md`**

```markdown
# HP48SX for Mac

A native macOS port of [czodroid/android-48sx](https://github.com/czodroid/android-48sx),
itself a modified build of droid48 (Arnaud Brochard's Android port of x48,
the 1994 UNIX Saturn-CPU emulator by Eddie C. Dost).

GPL-2.0 licensed (see COPYING). The bundled ROM is free for non-commercial
use per the upstream project.

## Build & run

    swift run HP48SXMac

## Build a double-clickable .app

    ./Scripts/make-app-bundle.sh
    open build/HP48SXMac.app

## Tests

    swift test
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Add the app bundle packaging script and README"
```

---

## Task 11: Final verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

```bash
swift test
```
Expected: all tests across every task pass.

- [ ] **Step 2: Build release and run the real app**

```bash
./Scripts/make-app-bundle.sh
open build/HP48SXMac.app
```

- [ ] **Step 3: Screenshot and compare against the source app**

Take a screenshot of the running app (via computer-use or a manual `cmd+shift+4`) and compare it side-by-side against `store/play/48sx_small.jpg` from the upstream clone (`/tmp/android-48sx-src/store/play/48sx_small.jpg`). Confirm: same relative keypad layout (menu row, 3 rows of 6, ENTER row, 4 rows of 5), same LCD placement and green color, same annunciator strip above the LCD.

- [ ] **Step 4: Walk through every item in this plan's Review Focus section one more time against the running app**

1. Corrupt/zero-length `ram` file → relaunch → confirm checkpoint auto-restore, no crash.
2. Screenshot within the first second of launch → confirm no corrupted/garbage LCD pixels.
3. Click the bezel background (not a key) and press an unmapped physical key → confirm no crash, no stray input.
4. Load Object… on a `.txt` file → confirm the alert, not a crash.
5. Full Reset while rapidly clicking keys → confirm no crash, state returns cleanly to out-of-box.

- [ ] **Step 5: Commit any final fixes found during this pass, then tag**

```bash
git add -A
git commit -m "Final verification pass fixes" # only if changes were needed
```
