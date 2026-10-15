# HP48SX for Mac

A native macOS port of [czodroid/android-48sx](https://github.com/czodroid/android-48sx)
(Olivier Sirol/czo), itself a modified build of droid48 (Arnaud Brochard's
Android port of x48, the 1994 UNIX Saturn-CPU emulator by Eddie C. Dost).

GPL-3.0 licensed (see COPYING). The bundled ROM is free for non-commercial
use per the upstream project. The app icon (`Assets/AppIcon.icns`) is
rasterized from upstream's own `store/img/icon_48sx.svg`, the real
launcher icon the Android app ships.

## Build & run

    swift run HP48SXMac

## Build a double-clickable .app

    ./Scripts/make-app-bundle.sh
    open build/HP48SXMac.app

## Tests

    swift test
