//! The corpus harness: one test per shared fixture (task 1.1 of `desktop-clients`).
//!
//! Every test here reads `packages/test-fixtures/manifest.json` and asserts the expectation
//! it records, exactly as `FormatsTests` does on iOS and `core/format` does on Android. The
//! list below is spelled out so that a fixture fails **by name**; `every_fixture_has_a_test`
//! fails when the manifest grows a fixture this list does not know.
//!
//! The manifest's `pdfs` and `audiobooks` tables are not here: PDF is item 9 of the core's
//! build order and audio comes later still (design.md, Decision 5), so neither has a reader
//! in wave 1.

mod corpus {
    pub mod comics;
    pub mod ebooks;
    pub mod filenames;
    pub mod manifest;
}

use corpus::manifest;

macro_rules! comic_fixtures {
    ($($name:ident => $file:literal),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let fixture = manifest::comic($file);
                if let Err(failure) = corpus::comics::check(fixture) {
                    panic!("{}: {failure}", fixture.file);
                }
            }
        )+
        const COMIC_FILES: &[&str] = &[$($file),+];
    };
}

macro_rules! ebook_fixtures {
    ($($name:ident => $file:literal),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let fixture = manifest::ebook($file);
                if let Err(failure) = corpus::ebooks::check(fixture) {
                    panic!("{}: {failure}", fixture.file);
                }
            }
        )+
        const EBOOK_FILES: &[&str] = &[$($file),+];
    };
}

macro_rules! filename_cases {
    ($($name:ident => $filename:literal),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let case = manifest::filename_case($filename);
                if let Err(failure) = corpus::filenames::check(case) {
                    panic!("{:?}: {failure}", case.filename);
                }
            }
        )+
        const FILENAME_CASES: &[&str] = &[$($filename),+];
    };
}

comic_fixtures! {
    comic_natural_sort => "comics/natural-sort.cbz",
    comic_nested_chapters => "comics/nested-chapters.cbz",
    comic_non_image_entries => "comics/non-image-entries.cbz",
    comic_mislabelled_zip => "comics/mislabelled-zip.cbr",
    comic_single_page => "comics/single-page.cbz",
    comic_double_page_spread => "comics/double-page-spread.cbz",
    comic_stored_entries => "comics/stored-entries.cbz",
    comic_password_protected => "comics/password-protected.cbz",
    comic_zip64 => "comics/zip64.cbz",
    comic_archive_comment => "comics/archive-comment.cbz",
    comic_data_descriptor => "comics/data-descriptor.cbz",
    comic_large_page => "comics/large-page.cbz",
    comic_truncated => "comics/truncated.cbz",
    comic_no_pages => "comics/no-pages.cbz",
    comic_unsupported_codec => "comics/unsupported-codec.cbz",
    comic_rar4_store => "comics/rar4-store.cbr",
    comic_rar5_store => "comics/rar5-store.cbr",
    comic_rar4_solid => "comics/rar4-solid.cbr",
    comic_rar4_comicinfo => "comics/rar4-comicinfo.cbr",
    comic_tar_store => "comics/tar-store.cbt",
    comic_tar_nested_chapters => "comics/tar-nested-chapters.cbt",
    comic_refused_cb7 => "comics/refused.cb7",
    comic_manga_metadata => "comics/manga-metadata.cbz",
    comic_japanese_no_direction => "comics/japanese-no-direction.cbz",
    comic_rar5_solid => "comics/rar5-solid.cbr",
    comic_rar4_compressed => "comics/rar4-compressed.cbr",
    comic_rar5_compressed => "comics/rar5-compressed.cbr",
}

ebook_fixtures! {
    ebook_fixture => "ebooks/fixture.epub",
    ebook_epub2 => "ebooks/epub2.epub",
    ebook_series => "ebooks/series.epub",
    ebook_one_sentence => "ebooks/one-sentence.epub",
    ebook_fixed_layout => "ebooks/fixed-layout.epub",
    ebook_spine_cover => "ebooks/spine-cover.epub",
    ebook_declared_rtl => "ebooks/declared-rtl.epub",
    ebook_no_package => "ebooks/no-package.epub",
}

filename_cases! {
    filename_series_issue_year => "Saga 003 (2012).cbz",
    filename_bare_number => "003.cbz",
    filename_volume_and_hash_issue => "Invincible v02 #011 (2004).cbr",
    filename_manga_chapter_and_group => "One Piece - c1044 (v104) [Scan Group].cbz",
    filename_spelled_volume => "Akira Vol. 3.cbz",
    filename_title_ending_in_digits => "Blame! 2001 (2001).cbz",
    filename_title_only => "Watchmen.cbz",
    filename_leading_zero_dropped => "Sandman #01 (1989).cbz",
    filename_spelled_chapter => "Berserk - Chapter 364.cbz",
}

/// The manifest and this file must agree, in both directions, or a new fixture would be
/// silently untested and a removed one silently asserted against nothing.
#[test]
fn every_fixture_has_a_test() {
    let manifest = manifest::manifest();
    let comics: Vec<&str> = manifest.comics.iter().map(|c| c.file.as_str()).collect();
    let ebooks: Vec<&str> = manifest.ebooks.iter().map(|e| e.file.as_str()).collect();
    let filenames: Vec<&str> = manifest
        .filenames
        .iter()
        .map(|f| f.filename.as_str())
        .collect();
    assert_eq!(
        comics, COMIC_FILES,
        "the comics list and this harness disagree"
    );
    assert_eq!(
        ebooks, EBOOK_FILES,
        "the ebooks list and this harness disagree"
    );
    assert_eq!(
        filenames, FILENAME_CASES,
        "the filenames table and this harness disagree"
    );
}

/// Every fixture the manifest names is on disk: the corpus is committed, not generated at
/// test time, so a missing file is a broken checkout rather than a parse failure.
#[test]
fn every_fixture_is_on_disk() {
    for file in COMIC_FILES.iter().chain(EBOOK_FILES) {
        assert!(manifest::path(file).is_file(), "{file} is missing on disk");
    }
}
