// swift-tools-version: 6.2
import PackageDescription

// The bundled reading typefaces, as a resource-only package.
//
// A path dependency rather than a copy inside the app package: Android reads the
// same directory as an asset source, and one copy on disk is the only way that
// stays true. The same arrangement as `third_party/libarchive`, and for the same
// reason.
//
// No platform floor beyond what the consumer needs — a `.ttf` has no minimum OS.
let package = Package(
    name: "StoryArcFonts",
    products: [
        .library(name: "StoryArcFonts", targets: ["StoryArcFonts"])
    ],
    targets: [
        .target(
            name: "StoryArcFonts",
            path: ".",
            exclude: ["README.md", "scripts", "Package.swift"],
            resources: [.copy("Literata.ttf"),
                        .copy("Literata-Italic.ttf"),
                        .copy("SourceSerif4.ttf"),
                        .copy("SourceSerif4-Italic.ttf"),
                        .copy("EBGaramond.ttf"),
                        .copy("EBGaramond-Italic.ttf"),
                        .copy("Bitter.ttf"),
                        .copy("Bitter-Italic.ttf"),
                        .copy("AtkinsonHyperlegible-Regular.ttf"),
                        .copy("AtkinsonHyperlegible-Italic.ttf"),
                        .copy("AtkinsonHyperlegible-Bold.ttf"),
                        .copy("AtkinsonHyperlegible-BoldItalic.ttf"),
                        // The licences ship with the app, which is what the OFL
                        // asks for and what `settings-and-about` promises.
                        .copy("OFL-literata.txt"),
                        .copy("OFL-sourceserif4.txt"),
                        .copy("OFL-ebgaramond.txt"),
                        .copy("OFL-bitter.txt"),
                        .copy("OFL-atkinsonhyperlegible.txt")]
        )
    ]
)
