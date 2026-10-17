//! Folder source scanning and reconciliation (task 2.2 of `desktop-clients`).
//!
//! A fixture folder built out of the shared corpus lists every publication, a second scan
//! over the store's records opens no archive, and the directory ceiling the watcher works
//! under is a named constant. The twin of iOS's `LibraryScannerTests`.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use storyarc_core::domain::{Publication, PublicationFormat, StreamingCapability};
use storyarc_core::io::CancelToken;
use storyarc_core::sources::local::{FolderScan, SkipReason, WATCH_DIRECTORY_LIMIT};
use storyarc_core::sources::snapshot::FolderSnapshot;
use storyarc_core::store::Store;

/// A 1×1 PNG, enough to be a page.
const PNG: &[u8] = &[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
];

fn copy(fixture: &str, to: &Path) {
    std::fs::copy(corpus::manifest::path(fixture), to).expect("copy a fixture");
}

/// A library: packed comics and an EPUB at the root, a refused CB7 and a solid RAR4, a
/// series folder of two issues, and an unpacked comic.
fn library() -> tempfile::TempDir {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path();
    copy("comics/natural-sort.cbz", &root.join("Saga 003 (2012).cbz"));
    copy(
        "comics/rar4-store.cbr",
        &root.join("Invincible v02 #011 (2004).cbr"),
    );
    copy("comics/tar-store.cbt", &root.join("Watchmen.cbt"));
    copy("ebooks/fixture.epub", &root.join("fixture.epub"));
    copy("comics/refused.cb7", &root.join("refused.cb7"));
    copy("comics/rar4-solid.cbr", &root.join("rar4-solid.cbr"));
    std::fs::write(root.join("notes.txt"), b"not a publication").unwrap();
    let series = root.join("Bone");
    std::fs::create_dir(&series).unwrap();
    copy("comics/single-page.cbz", &series.join("01.cbz"));
    copy("comics/natural-sort.cbz", &series.join("02.cbz"));
    let unpacked = root.join("Some Comic");
    std::fs::create_dir(&unpacked).unwrap();
    for page in ["p1.png", "p2.png", "p10.png"] {
        std::fs::write(unpacked.join(page), PNG).unwrap();
    }
    dir
}

fn scan(
    root: &Path,
    known: &HashMap<PathBuf, Publication>,
) -> storyarc_core::sources::local::ScanReport {
    FolderScan::new(root).scan(|path: &Path| known.get(path).cloned(), &CancelToken::new())
}

fn titles(publications: &[Publication]) -> Vec<&str> {
    publications
        .iter()
        .map(|p| p.display_title.as_str())
        .collect()
}

#[test]
fn a_fixture_folder_lists_every_publication() {
    let dir = library();
    let report = scan(dir.path(), &HashMap::new());

    assert_eq!(
        report.publications.len(),
        8,
        "{:?}",
        titles(&report.publications)
    );
    let by_title: HashMap<&str, &Publication> = report
        .publications
        .iter()
        .map(|p| (p.display_title.as_str(), p))
        .collect();

    // The root is not a series; the filename is.
    let saga = by_title["Saga #3"];
    assert_eq!(saga.format, PublicationFormat::Cbz);
    assert_eq!(saga.series.as_deref(), Some("Saga"));
    assert_eq!(saga.year, Some(2012));
    assert_eq!(saga.page_count, Some(12));
    assert!(saga.file_size.is_some() && saga.modified_at.is_some());
    assert!(
        saga.identity.content_digest.is_some(),
        "a file carries a digest"
    );
    assert!(
        !report
            .publications
            .iter()
            .any(|p| p.series.as_deref() == dir.path().file_name().and_then(|n| n.to_str()))
    );

    assert_eq!(by_title["Invincible #11"].format, PublicationFormat::Cbr);
    assert_eq!(by_title["Watchmen"].format, PublicationFormat::Cbt);
    let epub = by_title["Fixture Publication"];
    assert_eq!(epub.format, PublicationFormat::Epub);

    // A subfolder names the series when the filename does not.
    let bone: Vec<&Publication> = report
        .publications
        .iter()
        .filter(|p| p.series.as_deref() == Some("Bone"))
        .collect();
    assert_eq!(bone.len(), 2);
    let mut numbers: Vec<_> = bone.iter().map(|p| p.number.clone().unwrap()).collect();
    numbers.sort();
    assert_eq!(numbers, ["1", "2"]);

    // A folder of images is one publication, not a shelf, in natural page order.
    let unpacked = by_title["Some Comic"];
    assert_eq!(unpacked.format, PublicationFormat::ImageFolder);
    assert_eq!(unpacked.page_count, Some(3));
    assert_eq!(unpacked.cover_path.as_deref(), Some("p1.png"));
    assert!(
        unpacked.identity.content_digest.is_none(),
        "a folder has no bytes to digest"
    );

    // A refused publication is found rather than skipped, marked unopenable.
    let solid = by_title["rar4-solid"];
    assert_eq!(solid.streaming, StreamingCapability::Refused);
    assert!(!solid.is_openable());

    // A CB7 is skipped by name; a text file is not a publication and not a skip either.
    assert_eq!(report.skipped.len(), 1);
    assert!(report.skipped[0].path.ends_with("refused.cb7"));
    assert_eq!(
        report.skipped[0].reason,
        SkipReason::UnsupportedFormat("CB7".into())
    );
    assert!(report.unreadable_folders.is_empty());
    assert_eq!(report.opened, 8);
}

#[test]
fn a_second_scan_reads_no_archive() {
    let dir = library();
    let store = Store::in_memory().unwrap();
    let first = scan(dir.path(), &HashMap::new());
    assert_eq!(first.opened, 8);
    store
        .replace_publications("source", &first.publications)
        .unwrap();

    let known: HashMap<PathBuf, Publication> = store
        .publications("source")
        .unwrap()
        .into_iter()
        .map(|p| {
            (
                PathBuf::from(p.identity.normalized_path.clone().unwrap()),
                p,
            )
        })
        .collect();
    let second = scan(dir.path(), &known);
    assert_eq!(
        second.opened, 0,
        "every container was reconciled by size and date"
    );
    assert_eq!(second.reused, 8);
    assert_eq!(second.publications, first.publications);

    // A file whose size moved is the one container opened again.
    let changed = dir.path().join("Watchmen.cbt");
    let mut bytes = std::fs::read(&changed).unwrap();
    bytes.extend_from_slice(&[0; 1024]);
    std::fs::write(&changed, bytes).unwrap();
    let third = scan(dir.path(), &known);
    assert_eq!(third.opened, 1);
    assert_eq!(third.reused, 7);
}

#[test]
fn the_listing_holds_what_the_scan_found_and_what_it_refused_without_opening_anything() {
    let dir = library();
    let entries = FolderScan::new(dir.path()).entries();
    let names: Vec<String> = entries
        .iter()
        .map(|e| {
            Path::new(&e.path)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    for expected in [
        "Saga 003 (2012).cbz",
        "refused.cb7",
        "rar4-solid.cbr",
        "fixture.epub",
        "01.cbz",
        "Some Comic",
    ] {
        assert!(
            names.contains(&expected.to_owned()),
            "{expected} missing from {names:?}"
        );
    }
    assert!(!names.contains(&"notes.txt".to_owned()));
    assert!(
        !names.iter().any(|n| n.ends_with(".png")),
        "pages are not rows"
    );
    assert!(entries.iter().all(|e| e.modified.0 > 0));
    assert!(
        entries
            .iter()
            .filter(|e| !e.path.ends_with("Some Comic"))
            .all(|e| e.size > 0)
    );

    // The snapshot sees an arrival, a change and a removal, and nothing else.
    let before = FolderSnapshot::new(entries.clone());
    std::fs::remove_file(dir.path().join("Watchmen.cbt")).unwrap();
    copy("comics/single-page.cbz", &dir.path().join("New.cbz"));
    let mut bytes = std::fs::read(dir.path().join("refused.cb7")).unwrap();
    bytes.push(0);
    std::fs::write(dir.path().join("refused.cb7"), bytes).unwrap();
    let change = before
        .change(&FolderScan::new(dir.path()).entries())
        .expect("a walk that found something is believed");
    assert_eq!(change.added.len(), 1);
    assert!(change.added[0].path.ends_with("New.cbz"));
    assert_eq!(change.changed.len(), 1);
    assert!(change.changed[0].path.ends_with("refused.cb7"));
    assert_eq!(change.removed.len(), 1);
    assert!(change.removed[0].ends_with("Watchmen.cbt"));
    assert!(
        before.change(&[]).is_none(),
        "an empty walk over a full folder is not believed"
    );
}

#[test]
fn an_empty_or_missing_folder_finishes_and_an_unreadable_one_is_named() {
    let dir = tempfile::tempdir().unwrap();
    let empty = scan(dir.path(), &HashMap::new());
    assert!(empty.publications.is_empty() && empty.skipped.is_empty());
    let missing = scan(Path::new("/nowhere/at/all"), &HashMap::new());
    assert!(missing.publications.is_empty());
    assert_eq!(missing.unreadable_folders.len(), 1);
}

#[test]
fn a_cancelled_scan_stops_early() {
    let dir = library();
    let token = CancelToken::new();
    token.cancel();
    let report = FolderScan::new(dir.path()).scan(|_: &Path| None, &token);
    assert!(report.publications.is_empty());
    assert!(report.was_cancelled);
}

#[test]
fn the_watch_ceiling_is_the_phones_ninety_six_directories() {
    assert_eq!(WATCH_DIRECTORY_LIMIT, 96);
}
