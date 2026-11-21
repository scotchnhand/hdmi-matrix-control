// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MatrixKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MatrixKit", targets: ["MatrixKit"]),
    ],
    targets: [
        // holidays.json is a copy of docs/holidays.json (CI checks they match).
        .target(name: "MatrixKit", resources: [.copy("Resources/holidays.json")]),
        .testTarget(name: "MatrixKitTests", dependencies: ["MatrixKit"]),
    ]
)
