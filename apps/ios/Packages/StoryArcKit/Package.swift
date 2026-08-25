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
        .library(name: "ReaderFeature", targets: ["ReaderFeature"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        // The vendored libarchive RAR readers. A path dependency rather than a
        // copy inside this package: the same sources are compiled by the Android
        // build, and one copy is the only way that stays true.
        .package(path: "../../../../third_party/libarchive")
    ],
    targets: [
        .target(name: "DesignSystem", dependencies: ["StoryArcCore"]),
        .target(name: "StoryArcCore"),
        // ZIP, TAR, RAR headers and PDF are all ours or the platform's: ADR-0008
        // replaced ZIPFoundation with our own ranged-read ZIP reader, TAR and RAR
        // headers need no library, and PDF is PDFKit. libarchive is here for one
        // job only — decompressing a RAR entry, which is the one thing none of
        // the above can do.
        .target(
            name: "Formats",
            dependencies: [
                "StoryArcCore",
                .product(name: "CLibarchive", package: "libarchive"),
            ]
        ),
        .target(
            name: "LibraryFeature",
            dependencies: ["DesignSystem", "StoryArcCore", "Formats", "Persistence"],
            resources: [.process("Resources")]
        ),
        // One module per screen area, and no feature depends on another
        // (docs/architecture): the library opens the reader through the app layer.
        .target(
            name: "ReaderFeature",
            dependencies: ["DesignSystem", "StoryArcCore", "Formats", "Persistence"],
            resources: [.process("Resources")]
        ),
        // ADR-0006 names SwiftData here and Room on Android. The schema semantics
        // are shared; the implementations are not.
        .target(name: "Persistence", dependencies: ["StoryArcCore"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "StoryArcCoreTests", dependencies: ["StoryArcCore"]),
        .testTarget(name: "FormatsTests", dependencies: ["Formats"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "ReaderFeatureTests", dependencies: ["ReaderFeature"]),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
