// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Scotta",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Foundation")]),
        .target(name: "ScottaKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "scottad", dependencies: ["CSMC", "ScottaKit"], swiftSettings: v5),
        .executableTarget(name: "scotta", dependencies: ["ScottaKit"], swiftSettings: v5),
        .executableTarget(name: "ScottaApp", dependencies: ["ScottaKit"], swiftSettings: v5),
        .testTarget(name: "ScottaKitTests", dependencies: ["ScottaKit"]),
    ]
)
