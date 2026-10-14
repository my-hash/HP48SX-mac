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
                    // actions.c has `#ifdef __OPTIMIZE__ #error ... #endif` --
                    // the upstream CMakeLists.txt forces -O0 unconditionally,
                    // in Debug AND Release Android builds, for exactly this
                    // guard. Match that policy rather than stripping the
                    // guard: this 1994 interpreter loop relies on something
                    // that breaks under optimization, and nothing here needs
                    // the speed (the ROM boots and runs in milliseconds even
                    // unoptimized).
                    "-O0",
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
