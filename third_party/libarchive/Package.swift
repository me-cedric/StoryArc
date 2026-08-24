// swift-tools-version: 6.2
import PackageDescription

// A local package wrapping the vendored libarchive sources.
//
// It exists because SwiftPM will not compile C sources that live outside the
// package that declares them, and the sources must be shared with the Android
// build rather than copied. A path dependency solves both: one copy under
// `third_party/`, compiled by SwiftPM here and by CMake on the Android side.
//
// Only the RAR readers are here. See VENDORING.md for the file list, why each
// file is present, and how to refresh it.
let package = Package(
    name: "CLibarchive",
    products: [
        .library(name: "CLibarchive", targets: ["CLibarchive"])
    ],
    targets: [
        .target(
            name: "CLibarchive",
            publicHeadersPath: "include",
            cSettings: [
                // The hand-authored config.h next to the sources, rather than an
                // autoconf run SwiftPM has no way to perform.
                .define("HAVE_CONFIG_H"),
                // Gates libarchive's own internal-only declarations, including
                // the Android large-file shim.
                .define("__LIBARCHIVE_BUILD"),
                .headerSearchPath("."),
            ]
        )
    ]
)
