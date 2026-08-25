// swift-tools-version: 6.2
import PackageDescription

// The licence inventory, as a resource-only package.
//
// A path dependency rather than a copy inside the app package: Android stages the same
// directory into its assets, and one copy on disk is the only way that stays true. The
// same arrangement as `packages/fonts` and `third_party/libarchive`.
//
// It ships *in the app* rather than only in the repository because BSD and Apache require
// the notice to travel with the binary, and the SIL Open Font Licence requires its text
// to accompany the fonts.
let package = Package(
    name: "StoryArcLicences",
    products: [
        .library(name: "StoryArcLicences", targets: ["StoryArcLicences"])
    ],
    targets: [
        .target(
            name: "StoryArcLicences",
            path: ".",
            exclude: ["README.md", "Package.swift"],
            resources: [.copy("notices.json"), .copy("texts")]
        )
    ]
)
