// swift-tools-version: 6.0
import PackageDescription

// The parts of SQIA that are pure logic: pitch mapping, the note matrix, the
// dome geometry the stage is drawn on, and the project snapshot format. No
// UIKit, no audio, no network — so it builds and tests anywhere, and the
// golden fixtures taken from the web app can be checked on every commit.
let package = Package(
    name: "SQIACore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SQIACore", targets: ["SQIACore"])
    ],
    targets: [
        .target(name: "CSQIAAtomics"),
        .target(name: "SQIACore", dependencies: ["CSQIAAtomics"]),
        .testTarget(
            name: "SQIACoreTests",
            dependencies: ["SQIACore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
