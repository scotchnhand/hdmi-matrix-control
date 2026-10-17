// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MatrixKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "MatrixKit", targets: ["MatrixKit"]),
    ],
    targets: [
        .target(name: "MatrixKit"),
        .testTarget(name: "MatrixKitTests", dependencies: ["MatrixKit"]),
    ]
)
