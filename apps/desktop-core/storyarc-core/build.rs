//! Compiles the vendored libarchive sources into this crate (task 1.5 of `desktop-clients`).
//!
//! One copy of the sources serves three build systems: SwiftPM on iOS, CMake on Android and
//! the `cc` crate here (ADR-0018). `third_party/libarchive` is read-only from this lane and
//! `pnpm libarchive:pin` digests it, so nothing under it is edited; the desktop-only
//! configuration lives beside this file under `libarchive/`.
//!
//! Only the 26 sources the RAR readers need are vendored, so there is no format to compile
//! out. `archive_read_support_format_all()` is not among them, which is what keeps every
//! other parser out of reach of a crafted file.

use std::env;
use std::path::{Path, PathBuf};

fn main() {
    println!("cargo::rustc-check-cfg=cfg(storyarc_libarchive)");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    let crate_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let vendored = crate_dir.join("../../../third_party/libarchive/Sources/CLibarchive");
    assert!(
        vendored.join("config.h").is_file(),
        "vendored libarchive not found at {}: it is committed, not fetched; check the tree is complete",
        vendored.display()
    );

    let mut build = cc::Build::new();
    build
        .include(&vendored)
        .include(vendored.join("include"))
        // Gates libarchive's internal-only declarations, as the Swift and CMake builds do.
        .define("__LIBARCHIVE_BUILD", None)
        // Upstream code: its warnings are not ours to fix and must not fail a build.
        .warnings(false)
        .flag_if_supported("-w")
        // Decompression is the hot path of a page turn, so the C side is optimised even
        // when the Rust side is a debug build.
        .opt_level(2)
        // Per-function sections so the linker drops what the two RAR readers do not reach.
        .flag_if_supported("-ffunction-sections")
        .flag_if_supported("-fdata-sections");

    configure(&mut build, &target_os, &crate_dir);

    for source in sources(&vendored) {
        println!("cargo::rerun-if-changed={}", source.display());
        build.file(source);
    }
    println!("cargo::rerun-if-changed={}", vendored.display());
    println!("cargo::rerun-if-changed=libarchive");

    build.compile("storyarc_libarchive");
    println!("cargo::rustc-cfg=storyarc_libarchive");
}

/// Which `config.h` the sources see.
///
/// Apple hosts take the vendored header: it is the iOS configuration, and a macOS host is the
/// same platform. Linux takes the desktop-only header through libarchive's own
/// `PLATFORM_CONFIG_H` hook, which `archive_platform.h` reads before `config.h` — the one
/// way to override a quote-include that resolves its own directory before any `-I` path.
fn configure(build: &mut cc::Build, target_os: &str, crate_dir: &Path) {
    match target_os {
        "macos" | "ios" => {
            build.define("HAVE_CONFIG_H", None);
        }
        "linux" => {
            let header = crate_dir.join("libarchive/config-linux.h");
            println!("cargo::rerun-if-changed={}", header.display());
            let quoted = format!("\"{}\"", header.display());
            build.define("PLATFORM_CONFIG_H", quoted.as_str());
        }
        "windows" => {
            let header = crate_dir.join("libarchive/config-windows.h");
            let shim = crate_dir.join("libarchive/windows-shim.c");
            println!("cargo::rerun-if-changed={}", header.display());
            println!("cargo::rerun-if-changed={}", shim.display());
            // Forward slashes: a backslash before the closing quote breaks the cl command line.
            let quoted = format!("\"{}\"", header.display().to_string().replace('\\', "/"));
            build
                .define("PLATFORM_CONFIG_H", quoted.as_str())
                .file(shim);
            // archive_random.c's Windows branch calls BCryptGenRandom.
            println!("cargo::rustc-link-lib=bcrypt");
        }
        other => panic!("no libarchive configuration for target OS {other}"),
    }
}

/// Every vendored `.c` file, sorted so the archive's member order is reproducible.
fn sources(vendored: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(vendored)
        .expect("read the vendored libarchive directory")
        .map(|entry| entry.expect("directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "c"))
        .collect();
    files.sort();
    assert!(
        !files.is_empty(),
        "no C sources under {}",
        vendored.display()
    );
    files
}
