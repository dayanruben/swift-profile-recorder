// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-profile-recorder",
    platforms: [.macOS(.v11)],
    products: [
        .executable(
            name: "swipr-sample-conv",
            targets: ["ProfileRecorderSampleConverter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.32.3"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.2"),
    ],
    targets: [
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
    ],
    cxxLanguageStandard: .cxx14
)
