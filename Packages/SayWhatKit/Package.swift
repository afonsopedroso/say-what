// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SayWhatKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SayWhatKit", targets: ["SayWhatKit"]),
    ],
    targets: [
        .target(name: "SayWhatKit"),
        .testTarget(name: "SayWhatKitTests", dependencies: ["SayWhatKit"]),
    ]
)
