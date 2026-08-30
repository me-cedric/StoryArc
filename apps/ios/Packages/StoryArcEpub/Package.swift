// swift-tools-version: 6.2
import PackageDescription

// A second package, and only because of a platform floor.
//
// ADR-0005 puts Readium behind reflowable EPUB rendering, and the Readium Swift
// toolkit declares iOS support only. `StoryArcKit` also builds for macOS so its
// pure-Swift targets — parsers, ordering, the domain — can be tested on the host
// without a simulator, and SwiftPM validates a dependency graph for every
// platform the depending package claims. Adding Readium there fails the macOS
// resolution outright, and conditioning the target dependency does not help
// because the validation happens before the condition does.
//
// So the rendering engine lives in a package that claims iOS alone. Everything
// host-testable stays in `StoryArcKit`, and the app composes the two.
let package = Package(
    name: "StoryArcEpub",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "EpubReaderFeature", targets: ["EpubReaderFeature"])
    ],
    dependencies: [
        .package(path: "../StoryArcKit"),
        // The bundled typefaces. A path dependency because Android reads the same
        // directory as an asset source — see packages/fonts/README.md.
        .package(path: "../../../../packages/fonts"),
        // Exact, not `from:`. Readium pulls in eight transitive packages of its
        // own, every one of them on a floating minimum, and the app target has
        // no lockfile of its own until one is committed alongside it. An exact
        // requirement is the half of that a package manifest can state: the
        // version moves in a reviewed diff or it does not move.
        .package(url: "https://github.com/readium/swift-toolkit.git", exact: "3.11.0"),
    ],
    targets: [
        .target(
            name: "EpubReaderFeature",
            dependencies: [
                .product(name: "DesignSystem", package: "StoryArcKit"),
                .product(name: "StoryArcCore", package: "StoryArcKit"),
                .product(name: "Persistence", package: "StoryArcKit"),
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "ReadiumStreamer", package: "swift-toolkit"),
                .product(name: "ReadiumNavigator", package: "swift-toolkit"),
                .product(name: "StoryArcFonts", package: "fonts"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "EpubReaderFeatureTests", dependencies: ["EpubReaderFeature"]),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
