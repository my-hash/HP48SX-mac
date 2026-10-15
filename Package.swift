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
                    // Saturn's address space is 20-bit; every long/off_t/
                    // ssize_t value narrowed to int here is a file size,
                    // offset, or PC value that always fits. Harmless on
                    // this vendored code, but noisy on every build.
                    "-Wno-shorten-64-to-32",
                    // actions.c has `#ifdef __OPTIMIZE__ #error ... #endif` --
                    // the upstream CMakeLists.txt forces -O0 unconditionally,
                    // in Debug AND Release Android builds, for exactly this
                    // guard. Match that policy rather than stripping the
                    // guard: this 1994 interpreter loop relies on something
                    // that breaks under optimization, and nothing here needs
                    // the speed (the ROM boots and runs in milliseconds even
                    // unoptimized).
                    "-O0",
                    // SwiftPM's Xcode-compatible build system defines
                    // DEBUG for every target in a debug build regardless
                    // of any cSettings.define here, which switches on
                    // every vendored LOGD/LOGE call (originally Android's
                    // __android_log_print) -- stderr noise on every run,
                    // not useful without a device log viewer. -U after
                    // SwiftPM's own -D cancels it for this target only.
                    "-UDEBUG",
                ]),
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
