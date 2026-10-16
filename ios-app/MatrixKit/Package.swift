// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MatrixKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MatrixKit", targets: ["MatrixKit"]),
    ],
    targets: [
        .target(name: "MatrixKit"),
        .testTarget(name: "MatrixKitTests", dependencies: ["MatrixKit"]),
    ]
)
