// swift-tools-version: 6.2
import PackageDescription

// One package, one dependency graph. Every feature is a target here rather than
// a separate package so the module boundaries stay visible in a single file.
let package = Package(
    name: "StoryArcKit",
    defaultLocalization: "en",
    platforms: [
        // ADR-0003: iOS 26 is the floor. macOS is carried so the pure-Swift
        // targets can be built and tested on the host without a simulator, and
        // because ADR-0004 puts a Mac target on this same codebase later.
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Formats", targets: ["Formats"]),
        .library(name: "StoryArcCore", targets: ["StoryArcCore"]),
        .library(name: "LibraryFeature", targets: ["LibraryFeature"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "StoryArcCore"),
        // No third-party dependency: ADR-0008 replaced ZIPFoundation with our own
        // ranged-read ZIP reader, so the container parser is ours and inflate
        // comes from the platform's Compression framework.
        .target(name: "Formats", dependencies: ["StoryArcCore"]),
        .target(
            name: "LibraryFeature",
            dependencies: ["DesignSystem", "StoryArcCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "StoryArcCoreTests", dependencies: ["StoryArcCore"]),
        .testTarget(name: "FormatsTests", dependencies: ["Formats"]),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
