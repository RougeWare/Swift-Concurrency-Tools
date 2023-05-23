// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ConcurrencyTools",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ConcurrencyTools",
            targets: ["ConcurrencyTools"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/RougeWare/Swift-Optional-Tools.git", .upToNextMajor(from: "1.1.3")),
        .package(url: "https://github.com/RougeWare/Swift-Safe-Pointer.git", .upToNextMajor(from: "2.1.3")),
    ],
    targets: [
        // Targets are the basic buildsing blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ConcurrencyTools",
            dependencies: [
                .product(name: "OptionalTools", package: "Swift-Optional-Tools"),
                .product(name: "SafePointer", package: "Swift-Safe-Pointer"),
            ]),
        .testTarget(
            name: "ConcurrencyToolsTests",
            dependencies: ["ConcurrencyTools"]),
    ]
)
