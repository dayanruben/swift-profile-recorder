// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-unwind",
    platforms: [.macOS(.v11)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .executable(
            name: "swift-unwind",
            targets: ["swift-unwind"]),
        .executable(
            name: "sample-processor",
            targets: ["sample-processor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.32.3"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "swift-unwind",
            dependencies: [
                "CSampler", "CLibUnwind",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]),
        .executableTarget(
            name: "sample-processor",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
            ]),
        .target(
            name: "CLibUnwind",
            dependencies: []),
        .target(
            name: "CSampler",
            dependencies: ["CLibUnwind"]),
        .testTarget(
            name: "swift-unwindTests",
            dependencies: ["swift-unwind"]),
    ],
    cxxLanguageStandard: .cxx14
)
