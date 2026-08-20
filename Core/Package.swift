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
        // Optimised in debug as well, because this is where every sample is
        // computed and the audio thread's deadline does not care which
        // configuration is being built. Unoptimised, the same passage costs
        // five times as much — 0.54 against 0.10 times realtime — which is
        // the difference between a Run build that plays and one that
        // crackles. The setting lives here rather than in the Xcode project
        // so it cannot depend on whether project build settings reach a
        // package target.
        .target(
            name: "SQIACore",
            dependencies: ["CSQIAAtomics"],
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(
            name: "SQIACoreTests",
            dependencies: ["SQIACore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
