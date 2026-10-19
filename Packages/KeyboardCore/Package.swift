// swift-tools-version: 5.10
import PackageDescription

// Shared code used by both the app and the keyboard extension.
// Everything here is plain Swift (no UIKit), so `swift test` runs on the Mac.
let package = Package(
    name: "KeyboardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
    ],
    targets: [
        .target(name: "KeyboardCore"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
    ]
)
