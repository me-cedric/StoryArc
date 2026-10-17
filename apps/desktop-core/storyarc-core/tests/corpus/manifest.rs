//! `packages/test-fixtures/manifest.json`, typed.
//!
//! The corpus lives outside this crate on purpose: iOS, Android and this core read the same
//! files and assert the same recorded expectations, which is what stops three independent
//! implementations from privately disagreeing about what a correct parse is (ADR-0001).
//! The path is resolved from `CARGO_MANIFEST_DIR` rather than copied in.

use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use serde::Deserialize;

/// The corpus directory, found by walking up from this crate until `manifest.json` appears.
pub fn root() -> &'static Path {
    static ROOT: OnceLock<PathBuf> = OnceLock::new();
    ROOT.get_or_init(|| {
        let mut dir = Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf();
        loop {
            let corpus = dir.join("packages/test-fixtures");
            if corpus.join("manifest.json").is_file() {
                return corpus;
            }
            assert!(
                dir.pop(),
                "fixture corpus not found: expected packages/test-fixtures above {}",
                env!("CARGO_MANIFEST_DIR")
            );
        }
    })
}

/// A fixture's path on disk.
pub fn path(relative: &str) -> PathBuf {
    root().join(relative)
}

/// One entry of the manifest's `comics` list: what a correct parse of that archive yields.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Comic {
    pub file: String,
    pub pins: String,
    pub expected_page_count: Option<usize>,
    pub expected_page_order: Option<Vec<String>>,
    pub is_recoverable: Option<bool>,
    pub actual_container: Option<String>,
    pub has_comic_info: Option<bool>,
    pub expected_series: Option<String>,
    pub expected_comic_info: Option<ComicInfoExpectation>,
    pub spread_indices: Option<Vec<usize>>,
    pub is_solid: Option<bool>,
    pub is_streamable: Option<bool>,
    pub expected_refusal: Option<String>,
    pub expected_entry_names: Option<Vec<String>>,
    pub is_vendored: Option<bool>,
    /// Entries that looked like pages and could not be read, which `publication-formats`
    /// requires an archive to count rather than hide.
    pub expected_skipped_page_count: Option<usize>,
    /// What the archive's undecodable page should be named as.
    pub expected_undecodable_codec: Option<String>,
    /// The page's size in pixels, where the fixture pins one. Read by `tests/decode.rs`.
    #[allow(dead_code)]
    pub page_dimensions: Option<Vec<u32>>,
    /// The colour at the centre of the first page, which every decoder must reproduce. Read
    /// by `tests/decode.rs`.
    #[allow(dead_code)]
    pub expected_page_pixel: Option<Vec<i64>>,
}

/// The `ComicInfo.xml` fields a fixture records. Every one is optional in the file too.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ComicInfoExpectation {
    pub series: Option<String>,
    pub number: Option<String>,
    pub volume: Option<i64>,
    pub title: Option<String>,
    pub summary: Option<String>,
    pub writers: Option<Vec<String>>,
    pub penciller: Option<String>,
    pub publisher: Option<String>,
    pub year: Option<i64>,
    pub month: Option<i64>,
    pub day: Option<i64>,
    pub page_count: Option<i64>,
    pub language: Option<String>,
    pub reading_direction: Option<String>,
    pub cover_page_index: Option<usize>,
    pub double_page_indices: Option<Vec<usize>>,
}

/// One entry of the manifest's `ebooks` list.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ebook {
    pub file: String,
    pub pins: String,
    pub epub_version: u32,
    pub expected_spine_count: usize,
    pub expected_title: Option<String>,
    pub expected_author: Option<String>,
    pub expected_language: Option<String>,
    pub expected_identifier: Option<String>,
    pub expected_publisher: Option<String>,
    pub expected_description: Option<String>,
    pub expected_series: Option<String>,
    pub expected_series_index: Option<String>,
    pub expected_spine_hrefs: Option<Vec<String>>,
    pub expected_toc_titles: Option<Vec<String>>,
    pub expected_cover_href: Option<String>,
    /// The cover once the first spine item has been consulted, which `publication-formats`
    /// falls back to when a publication declares none.
    pub expected_spine_cover_href: Option<String>,
    pub has_nav_document: bool,
    pub has_cover_image: bool,
    pub is_fixed_layout: bool,
    pub expected_refusal: Option<String>,
    /// `"rtl"`, `"ltr"`, or absent for a fixture that declares no direction at all.
    pub expected_page_progression_direction: Option<String>,
}

/// One case of the manifest's `filenames` table. Needs no file on disk: filename inference
/// is a pure function over a string, so what the corpus pins is the table of cases.
#[derive(Debug, Deserialize)]
pub struct FilenameCase {
    pub filename: String,
    pub series: Option<String>,
    pub number: Option<String>,
    pub volume: Option<i64>,
    pub year: Option<i64>,
    /// Why this case is in the table, so a failure says what broke.
    pub why: String,
}

/// One entry of the manifest's `pdfs` list: what both phones read from that file (task 4.4).
/// Read by `tests/pdf.rs` alone, so the other binaries that share this module allow it.
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Pdf {
    pub file: String,
    pub pins: String,
    pub expected_page_count: usize,
    pub expected_page_size_points: [u32; 2],
    pub has_text_layer: bool,
    pub expected_page_text: Option<Vec<String>>,
    pub expected_outline_titles: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub comics: Vec<Comic>,
    pub ebooks: Vec<Ebook>,
    #[allow(dead_code)]
    pub pdfs: Vec<Pdf>,
    pub filenames: Vec<FilenameCase>,
}

/// The manifest, read once. A corpus that cannot be read makes every test meaningless, so
/// failing loudly here beats each fixture reporting its own confusing error.
pub fn manifest() -> &'static Manifest {
    static MANIFEST: OnceLock<Manifest> = OnceLock::new();
    MANIFEST.get_or_init(|| {
        let text = std::fs::read_to_string(path("manifest.json"))
            .expect("read the shared corpus manifest");
        serde_json::from_str(&text).expect("parse the shared corpus manifest")
    })
}

pub fn comic(file: &str) -> &'static Comic {
    manifest()
        .comics
        .iter()
        .find(|fixture| fixture.file == file)
        .unwrap_or_else(|| panic!("no comic fixture named {file} in manifest.json"))
}

pub fn ebook(file: &str) -> &'static Ebook {
    manifest()
        .ebooks
        .iter()
        .find(|fixture| fixture.file == file)
        .unwrap_or_else(|| panic!("no ebook fixture named {file} in manifest.json"))
}

#[allow(dead_code)]
pub fn pdf(file: &str) -> &'static Pdf {
    manifest()
        .pdfs
        .iter()
        .find(|fixture| fixture.file == file)
        .unwrap_or_else(|| panic!("no PDF fixture named {file} in manifest.json"))
}

pub fn filename_case(filename: &str) -> &'static FilenameCase {
    manifest()
        .filenames
        .iter()
        .find(|case| case.filename == filename)
        .unwrap_or_else(|| panic!("no filename case {filename:?} in manifest.json"))
}
