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
