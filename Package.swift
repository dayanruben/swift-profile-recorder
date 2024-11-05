// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-profile-recorder",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "ProfileRecorder", targets: ["ProfileRecorder"]),
        .executable(
            name: "swipr-sample-conv",
            targets: ["ProfileRecorderSampleConverter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.75.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.24.1"),
    
    ],
    targets: [
        // MARK: - Executables
        .executableTarget(
            name: "swipr-demo",
            dependencies: [
                "ProfileRecorder",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]),
        .executableTarget(
            name: "swipr-mini-demo",
            dependencies: [
                "ProfileRecorder",
                .product(name: "NIO", package: "swift-nio"),
            ]),
        .executableTarget(
            name: "ProfileRecorderSampleConverter",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                
            ]),

        // MARK: - Library targets
        .target(
            name: "ProfileRecorder",
            dependencies: [
                .targetItem(
                    name: "CProfileRecorderSampler",
                    // We currently only support Linux but we compile just fine on macOS too.
                    // llvm unwind doesn't currently compile on watchOS, presumably because of arm64_32.
                    // Let's be a little conservative and allow-list macOS & Linux.
                    condition: .when(platforms: [.macOS, .linux])
                ),
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .target(
            name: "CProfileRecorderLibUnwind",
            dependencies: [],
            cSettings: [.define("_LIBUNWIND_IS_NATIVE_ONLY")],
            cxxSettings: [.define("_LIBUNWIND_IS_NATIVE_ONLY")]
        ),
        .target(
            name: "CProfileRecorderSampler",
            dependencies: [
                .targetItem(
                    name: "CProfileRecorderLibUnwind",
                    // We currently only support Linux but we compile just fine on macOS too.
                    // llvm unwind doesn't currently compile on watchOS, presumably because of arm64_32.
                    // Let's be a little conservative and allow-list macOS & Linux.
                    condition: .when(platforms: [.macOS, .linux])
                ),
            ]),

        // MARK: - Tests
        .testTarget(name: "ProfileRecorderTests",
                    dependencies: [
                        "ProfileRecorder",
                        .product(name: "Atomics", package: "swift-atomics"),
                        .product(name: "NIO", package: "swift-nio"),
                    ]),
    ],
    cxxLanguageStandard: .cxx14
)

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.enableExperimentalFeature("StrictConcurrency=complete"))
    target.swiftSettings = settings
}
