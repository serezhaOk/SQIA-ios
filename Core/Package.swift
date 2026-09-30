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
        .library(name: "SQIACore", targets: ["SQIACore"]),
        // The synth core on its own, for SQIA Lab (../SQIA-Lab), which
        // designs sounds with the same code that plays them here.
        .library(name: "SQIASound", targets: ["SQIASound"]),
    ],
    targets: [
        .target(name: "CSQIAAtomics"),
        // The voices the sounds from SQIA Lab are made of: Plaits and the
        // Rings reverb (Mutable Instruments, MIT — see NOTICE.md) behind a
        // C header, so Swift needs no C++ interop and Android can reach the
        // same code over JNI.
        .target(
            name: "SQIASound",
            exclude: [
                "vendor/mi/UPSTREAM.txt",
                "vendor/mi/stmlib/LICENSE",
            ],
            cxxSettings: [
                .headerSearchPath("vendor/mi"),
                // stmlib's portable paths instead of Cortex-M4 intrinsics,
                // and the flash access stubbed out.
                .define("TEST"),
                // Optimised in debug for the same reason as SQIACore below;
                // the vendored sources are left exactly as published, so
                // their warnings are not ours to fix. Plaits' flash stub
                // calls printf without including stdio, which Apple's
                // headers forgive and the Linux CI's may not.
                .unsafeFlags(["-O2", "-w", "-include", "cstdio"]),
            ]
        ),
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
            dependencies: ["CSQIAAtomics", "SQIASound"],
            resources: [.copy("Sounds")],
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        .testTarget(
            name: "SQIACoreTests",
            dependencies: ["SQIACore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SQIASoundTests",
            dependencies: ["SQIASound"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
