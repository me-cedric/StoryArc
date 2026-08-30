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
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "Catalogue", targets: ["Catalogue"]),
        .library(name: "Kavita", targets: ["Kavita"]),
        .library(name: "Smb", targets: ["Smb"]),
    ],
    dependencies: [
        // The vendored libarchive RAR readers. A path dependency rather than a
        // copy inside this package: the same sources are compiled by the Android
        // build, and one copy is the only way that stays true.
        .package(path: "../../../../third_party/libarchive"),
        // The bundled typefaces and the licence inventory, both read by Android from
        // the same directories. One copy on disk is the only way that stays true.
        .package(path: "../../../../packages/licences"),
        // `network-share` needs SMB 2/3, which iOS has no API for. Pure Swift and
        // MIT, so no FFI boundary and no licence to argue about. ADR-0010.
        .package(
            url: "https://github.com/kishikawakatsumi/SMBClient.git",
            from: "0.3.1"
        )
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
        // The SMB seam. Everything above it works against `RandomAccessSource`
        // and learns nothing about the protocol. ADR-0010.
        .target(
            name: "Smb",
            dependencies: [
                "Formats",
                "StoryArcCore",
                .product(name: "SMBClient", package: "SMBClient"),
            ]
        ),
        .target(
            name: "LibraryFeature",
            dependencies: ["DesignSystem", "StoryArcCore", "Formats", "Persistence", "Catalogue", "Kavita", "Smb"],
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
        .target(name: "Catalogue", dependencies: ["StoryArcCore"]),
        .target(name: "Kavita", dependencies: ["StoryArcCore", "Catalogue"]),
        .target(
            name: "SettingsFeature",
            dependencies: [
                "DesignSystem", "StoryArcCore", "Persistence",
                .product(name: "StoryArcLicences", package: "licences"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SmbTests",
            dependencies: ["Smb"]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "StoryArcCoreTests", dependencies: ["StoryArcCore"]),
        .testTarget(name: "FormatsTests", dependencies: ["Formats"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "CatalogueTests", dependencies: ["Catalogue"]),
        .testTarget(name: "KavitaTests", dependencies: ["Kavita"]),
        .testTarget(name: "ReaderFeatureTests", dependencies: ["ReaderFeature"]),
        .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature"]),
        // The adaptive layout decides what a sidebar holds, and there is no simulator in
        // this repository's loop. What can be asserted without one is asserted here.
        // `Catalogue` and `Kavita` are here because what the library does with an address
        // — which of the two a pasted URL is — is asserted against both parsers.
        .testTarget(
            name: "LibraryFeatureTests",
            dependencies: ["LibraryFeature", "Catalogue", "Kavita", "Persistence", "StoryArcCore"]
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .swiftLanguageMode(.v6),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
    ]
}
