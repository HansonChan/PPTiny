// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PPTiny",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PPTiny", targets: ["PPTiny"]),
        .executable(name: "PPTinyCLI", targets: ["PPTinyCLI"])
    ],
    targets: [
        .executableTarget(
            name: "PPTiny",
            dependencies: ["PPTinyCore"],
            path: "Sources/PPTiny"
        ),
        .executableTarget(
            name: "PPTinyCLI",
            dependencies: ["PPTinyCore"],
            path: "Sources/PPTinyCLI"
        ),
        .target(
            name: "PPTinyCore",
            path: "Sources/PPTinyCore"
        )
    ]
)
