// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AeroSpaceIconz",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "IconzCore"),
        .executableTarget(name: "AeroSpaceIconz", dependencies: ["IconzCore"]),
        .testTarget(name: "IconzCoreTests", dependencies: ["IconzCore"]),
        .testTarget(name: "AeroSpaceIconzTests", dependencies: ["AeroSpaceIconz"]),
    ]
)
