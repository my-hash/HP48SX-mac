# HP48SX Mac Port — Design Spec

Date: 2026-10-14
Status: Approved by user, pending implementation plan

## Source project

[`czodroid/android-48sx`](https://github.com/czodroid/android-48sx) — an Android
emulator of the HP48 SX, which is itself a modified build of `droid48` (Arnaud
Brochard's Android port of `x48`, the 1994 UNIX Saturn-CPU emulator by Eddie C.
Dost). GPL-2.0 licensed; ROM asset is "free for non-commercial use" per the
upstream README.

## Goal

A native macOS Swift/AppKit app that looks and behaves like the Android app —
same keypad layout, same LCD proportions, same reachable feature set — for
personal use. Not a rewrite of the emulator; a port of the shell around an
unchanged emulator core.

## Why this is tractable

The Android app's JNI surface is 12 functions (`X48.java`): `startHPEmulator`,
`resetHPEmulator`, `saveState`, `stopHPEmulator`, `buttonPressed`,
`buttonReleased`, `registerClass`, `fillAudioData`, `fillScreenData`,
`flipScreen`, `loadProg`, `getExternalPath`, `setBlankColor`. Everything behind
that surface (~22.5k lines: `emulate.c`, `memory.c`, `lcd.c`, `rpl.c`,
`debugger.c`, `disasm.c`, `serial.c`, `timer.c`, `register.c`, `romio.c`,
`resources.c`, `init.c`, `actions.c`, `binio.c`, `options.c`, `x48.c`) is
plain, portable ANSI C inherited from the original UNIX `x48` — not
Android-specific. Swift calls C directly via a bridging header; no JNI
equivalent is needed at all.

**Scope clarification on "full feature parity":** `X48.java`'s actual menu
(`onCreateOptionsMenu`/`onMenuItemSelected`) never exposes an interactive
debugger, disassembler, or serial/Kermit transfer UI — those C modules
(`debugger.c`, `disasm.c`, `serial.c`) are vendored only because `main.c`'s
emulate loop unconditionally calls into `debug()`/`emulate_debug()`; their
interactive capabilities are dead weight in the shipped Android app too.
"Full feature parity" therefore means matching everything `X48.java` actually
does, enumerated below — not adding new debugger/RPL-browser/serial UI that
the source app never shipped.

## What `X48.java` actually does (the parity target)

- **Menu:** Full Reset (wipe `hp48`/`ram`/`rom`/`port1`/`port2`, re-copy
  bundled assets), Restore Checkpoint, Save Checkpoint, Settings, Load Object
  (file picker → `loadProg(path)` → auto-press ON), Save backup as `.zip`,
  Restore backup from `.zip`, Quit.
- **Settings:** Save on Exit (default on), memory card Port 1 / Port 2 —
  each either "None/Delete" or "128kB" (`port_1_values`/`port_2_values` in
  `strings.xml`; both default to `0`/None).
- **First-run / persistence:** on first launch, copy bundled `hp48` (state
  file), `rom` (256KB fixed), `ram` (32KB fixed) into a config directory, with
  size validation (`AssetUtil.isFilesReady`/`copyAsset`). A `checkpoint/`
  subfolder holds an auto-backup created on first run, used by
  Restore/Save Checkpoint. `verifyNoFileZero` guards against corrupt
  zero-length state files by forcing a checkpoint restore.
- **Input:** `HPView` touch/keypad hit-testing (49 keys, `k01.png`–`k49.png`)
  plus a physical-keyboard mapping (`actionKey`: digits, letters A–Z, Enter,
  Del→key 28, period→46, space→47, arrow keys→cursor keys 10/15/16/17,
  dpad-center→Enter).
- **Display:** LCD bitmap (131×64 real pixels, bundled as a 262×142 RGB565
  buffer: 2x-scaled LCD + 14px icon strip) plus 6 annunciator icon overlays
  (`ann01.png`–`ann06.png`) at fixed x-offsets (0, 21, 45, 67, 91, 112 ×
  `lcd_ratio`).

**Explicitly not ported** (Android-only concerns that don't apply to a fixed
desktop window with mouse + keyboard): `keybLite` compact mode, landscape
layout, haptic feedback, `fullScreen`/immersive system-UI toggling,
multitouch. Contrast (`contrast_values` in `strings.xml`) is defined but
never wired into any Settings UI in the source app either — left at its
default, same as upstream.

## Architecture

### Repo layout

New SwiftPM project, its own repo, at `~/HP48SX-mac` (per the user's existing
convention: a new project is always a new repo, never mixed into an existing
one).

```
HP48SX-mac/
  Package.swift
  COPYING                      (GPL-2.0, carried over — this is GPL-derived code)
  Sources/
    CEmu/                      C target: vendored emulator core
      include/CEmu.h           umbrella header, the Swift-facing C API
      *.c, *.h                 ported from android-48sx's app/src/main/cpp/,
                                minus main.c's JNI glue
    HP48SXMac/                 Swift executable target (AppKit)
      main.swift               NSApplication bootstrap
      AppDelegate.swift
      EmulatorBridge.swift     thin Swift wrapper over CEmu: start/stop/reset/
                               save, buttonPressed/Released, fillScreenData,
                               flipScreen, loadProg, setBlankColor; runs the
                               emulate()/debug() loop on a background thread;
                               replaces the Java waitEvent/pauseEvent JNI
                               callback with a direct Swift-side key queue
      CalculatorView.swift     NSView: 1:1 port of HPView's draw + hit-test
                               logic (LCD blit, 49 keycaps, annunciators,
                               mouseDown/Up, keyDown/Up)
      KeyLayout.swift          the fixed-size layout math (see Dimensions)
      MenuBuilder.swift        NSMenu mirroring X48's options menu
      PreferencesWindow.swift  Save on Exit, Port 1/2 size pickers
      AppPaths.swift           config dir, first-run asset copy, checkpoint
                               save/restore/full-reset, zero-length-file guard
  Resources/
    rom, ram, hp48             vendored bundled files (same bytes as upstream)
    Keycaps/k01.png … k49.png, ann01.png … ann06.png   (same PNGs, same look)
```

### Emulator core (`CEmu` target)

Vendor `actions.c, binio.c, device.c, emulate.c, init.c, lcd.c, memory.c,
options.c, register.c, resources.c, romio.c, rpl.c, serial.c, timer.c, x48.c,
debugger.c, disasm.c` and their headers essentially unchanged — this is
already portable ANSI C. Two changes only:

1. Delete `main.c`'s `Java_org_czo_droid48sx_X48_*` functions, the `main()`
   entry point, and `#include <jni.h>`/`<android/log.h>`.
2. Replace the Android `LOGD`/`LOGE` macros with a tiny local header that
   `fprintf(stderr, …)`s instead.

Expose via `CEmu.h`: `init_emulator()`, `init_active_stuff()`, `emulate()`,
`emulate_debug()`, `debug()`, `do_reset()`, `write_files()` (= saveState),
`button_pressed(int)`, `button_released(int)`, `read_bin_file(char*)` (=
loadProg), and the screen/audio/contrast functions currently implemented as
JNI shims in `lcd.c` (`Java_..._fillScreenData`, `Java_..._flipScreen`,
`Java_..._setBlankColor`) and `device.c` (`Java_..._fillAudioData`) — these
get the same JNI-stripping treatment as `main.c`, replacing the JNI
parameter/return marshalling with plain C signatures while keeping their
bodies (which already just read `disp_buf_short`/write `config_dir`, etc.).

The blocking `waitEvent`/`pauseEvent` callback into Java (`x48.c:627`,
`actions.c:660,679`, via `android_callback`/`CallVoidMethod`) is replaced with
direct calls into two small Swift-exposed C functions backed by a
thread-safe queue — same control flow (the emulate thread blocks when idle,
wakes on a queued key event), no JNI indirection.

### Swift/AppKit shell

- One `NSWindow`, fixed size, not resizable, titled "48SX".
- `CalculatorView: NSView` draws (in order): bezel background rects (colors
  ported verbatim: func `rgb(83,81,82)`, central `rgb(57,57,56)`, LCD green
  `rgb(189,195,165)`), the LCD bitmap (converted each frame from the
  emulator's RGB565 short buffer to a `CGImage` and drawn into the LCD rect),
  all 49 keycap images at their computed positions, a pressed-key highlight
  (rounded rect, port of `HPView`'s `paint`/`drawRoundRect`), and the 6
  annunciator icons when active.
- Mouse: `mouseDown`/`mouseUp` hit-test against the same `buttons_coords`
  table `HPView` computes, single-touch model (matches the non-multitouch
  Android code path — a mouse presses one key at a time, same as it already
  behaves on older/non-multitouch Android devices).
- Keyboard: `keyDown`/`keyUp` port of `HPView.actionKey`'s switch statement,
  translated from Android `KeyEvent` codes to macOS `NSEvent.charactersIgnoringModifiers`/`keyCode`.
- A `Timer` (or `CVDisplayLink`) firing at ~25fps (matching Android's
  `Thread.sleep(40)`) pulls fresh screen/annunciator data from the bridge and
  calls `setNeedsDisplay(true)`.

### Dimensions (preserving look and feel)

The Android view is responsive — there is no single canonical pixel size
even in the source app, since `HPView.refreshMainScreen` recomputes
`lcd_ratio = width / 135` on every resize. "Keep the dimensions" is
implemented as: preserve every *relative* proportion from that same ratio
system, evaluated once at a fixed base size instead of live per-resize.

Derivation:
- `lcd_ratio = 2` (fixed) — the bundled LCD bitmap is already a 262×142
  (131×64 real pixels × 2) buffer, so ratio 2 renders it at native resolution
  with no blur/interpolation.
- `start_w = 131 × 2 = 262`, `start_h = 73 × 2 = 146` — LCD + icon-strip
  region, matching `HPView`'s current constants.
- Content width `w = 135 × 2 = 270` (the 135 includes the few px of side
  bezel beyond the pure 131px LCD that the current key-image set uses).
- 9 equal key rows below the LCD region (`usable_h / 9`, per `HPView`'s row
  math: 1 menu row of 6 + 3 rows of 6 + 1 ENTER/nav row + 4 rows of 5 = 9).
  `regular_key_height` is set to `w / 6 = 45` — i.e., the 6-across rows
  render square keys, matching their 115×110px source art (near-square); the
  5-across and ENTER rows come out proportionally wider, matching the real
  HP48SX's bottom rows.
- Design-unit silhouette: **270 × 551** (`270 × (146 + 9×45)`), aspect
  ≈1:2.04 — close to the real HP48SX body's ≈1:2.2.
- Scaled ×1.333 to a comfortable fixed desktop window: **360 × 735pt**.

This one scale factor is a named constant so the overall size can be tuned
later without touching any layout math.

### Persistence

Config dir: `~/Library/Application Support/HP48SX/`. On first launch, copy
bundled `rom`/`ram`/`hp48` from the app's `Resources/` into it (size checks:
ROM 256KB, RAM 32KB, matching `AssetUtil.copyAsset`/`isFilesReady`). A
`checkpoint/` subfolder holds the auto-backup; Full Reset, Save/Restore
Checkpoint, and the zero-length-file guard (`verifyNoFileZero`) port
directly from `X48.java`. Save/Restore `.zip` backup shells out to the
system `/usr/bin/zip`/`/usr/bin/unzip` via `Process` — no new dependency,
same membership (`hp48`/`ram`/`rom`/`port1`/`port2`).

### Testing

This is a UI + native-emulator app, not unit-test-shaped. Verification plan:
1. One headless smoke check in the `CEmu` target: `init_emulator()`, run a
   handful of `emulate()` cycles, assert `fillScreenData` produces non-zero,
   changing output (confirms the C core links and actually runs before any
   UI is built on top of it).
2. Build and run the real app, screenshot it via computer-use to visually
   confirm layout/look against the original app's screenshot
   (`store/play/48sx_small.jpg`) before calling the port done.

## Out of scope (v1)

- Interactive debugger/disassembler/serial-Kermit UI (not in the source app
  either — see Scope clarification above).
- keybLite compact mode, landscape layout, haptics, fullScreen/immersive
  system-UI toggling, multitouch, contrast UI (all Android-only or already
  unreachable in the source app).
- Any ROM other than the bundled HP48SX ROM.
