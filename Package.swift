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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.32.3"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.2"),
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
            name: "ProfileRecorderSampleConverter",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
            ]),

        // MARK: - Library targets
        .target(
            name: "ProfileRecorder",
            dependencies: [
                "CProfileRecorderSampler",
                .product(name: "NIO", package: "swift-nio"),
            ]),
        .target(
            name: "CProfileRecorderLibUnwind",
            dependencies: []),
        .target(
            name: "CProfileRecorderSampler",
            dependencies: ["CProfileRecorderLibUnwind"]),

        // MARK: - Tests
        .testTarget(name: "ProfileRecorderTests",
                    dependencies: [
                        "ProfileRecorder",
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
