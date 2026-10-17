//! The public Rust API the Linux app calls, `storyarc_core::library`, asserted against the
//! shared corpus. The same operations cross the C seam for the Windows app
//! (`storyarc-ffi`); these tests are the Rust side of that contract.

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

use corpus::manifest;
use storyarc_core::domain::{PublicationFormat, ReadingPosition, ReadingProgress, Timestamp};
use storyarc_core::formats::PageCodec;
use storyarc_core::image::PageDecodeError;
use storyarc_core::io::CancelToken;
use storyarc_core::library::{FolderSource, LibraryError, OpenPublication, ProgressStore};

fn scratch_folder() -> tempfile::TempDir {
    let folder = tempfile::tempdir().unwrap();
    for name in ["large-page.cbz", "natural-sort.cbz", "refused.cb7"] {
        std::fs::copy(
            manifest::path(&format!("comics/{name}")),
            folder.path().join(name),
        )
        .unwrap();
    }
    folder
}

#[test]
fn a_folder_source_lists_its_publications_and_names_what_it_skipped() {
    let folder = scratch_folder();
    let source = FolderSource::open(folder.path(), &CancelToken::new()).unwrap();
    let titles: Vec<&str> = source
        .publications()
        .iter()
        .map(|publication| publication.display_title.as_str())
        .collect();
    assert_eq!(titles.len(), 2, "{titles:?}");
    assert!(
        source
            .publications()
            .iter()
            .all(|p| p.format == PublicationFormat::Cbz)
    );
    assert_eq!(source.skipped().len(), 1, "the CB7 is named, not hidden");
    let json: serde_json::Value = serde_json::from_str(&source.records_json()).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 2);
    assert!(json[0]["displayTitle"].is_string());
    assert!(json[0]["identity"]["normalizedPath"].is_string());
}

#[test]
fn a_rescan_of_an_unchanged_folder_reads_no_archive() {
    let folder = scratch_folder();
    let mut source = FolderSource::open(folder.path(), &CancelToken::new()).unwrap();
    let report = source.rescan(&CancelToken::new());
    assert_eq!(report.opened, 0);
    assert_eq!(report.reused, 2);
    assert_eq!(source.publications().len(), 2);
}

#[test]
fn a_folder_that_is_not_there_is_refused() {
    let error = FolderSource::open("/no/such/storyarc/folder", &CancelToken::new()).unwrap_err();
    assert!(matches!(error, LibraryError::NotFound(_)), "{error:?}");
}

#[test]
fn a_publication_opens_with_its_page_count_and_metadata() {
    let opened = OpenPublication::open(manifest::path("comics/manga-metadata.cbz")).unwrap();
    let fixture = manifest::comic("comics/manga-metadata.cbz");
    assert_eq!(Some(opened.page_count()), fixture.expected_page_count);
    assert_eq!(
        opened.publication().series.as_deref(),
        fixture.expected_series.as_deref()
    );
    let json: serde_json::Value = serde_json::from_str(&opened.metadata_json()).unwrap();
    assert_eq!(json["pageCount"], fixture.expected_page_count.unwrap());
}

#[test]
fn a_page_decodes_to_rgba_with_its_size() {
    let opened = OpenPublication::open(manifest::path("comics/large-page.cbz")).unwrap();
    let page = opened.decode_page(0, Some(600)).unwrap();
    assert_eq!((page.width, page.height), (400, 600));
    assert_eq!(page.rgba.len(), 400 * 600 * 4);
    let size = opened.page_size(0).unwrap();
    assert_eq!((size.width, size.height), (2000, 3000));
}

#[test]
fn a_page_past_the_end_and_a_page_nothing_decodes_are_named() {
    let opened = OpenPublication::open(manifest::path("comics/large-page.cbz")).unwrap();
    assert!(matches!(
        opened.decode_page(1, None).unwrap_err(),
        LibraryError::PageOutOfRange { index: 1, count: 1 }
    ));
    let jxl = OpenPublication::open(manifest::path("comics/unsupported-codec.cbz")).unwrap();
    let error = jxl.decode_page(1, None).unwrap_err();
    assert_eq!(
        error,
        LibraryError::Decode(PageDecodeError::Unsupported(PageCodec::JpegXl))
    );
    assert!(error.to_string().contains("JPEG XL"), "{error}");
}

#[test]
fn a_format_that_is_not_paged_is_refused_by_name() {
    let error = OpenPublication::open(manifest::path("comics/refused.cb7")).unwrap_err();
    assert!(error.to_string().contains("CB7"), "{error}");
}

#[test]
fn progress_written_through_the_store_reads_back() {
    let folder = tempfile::tempdir().unwrap();
    let opened = OpenPublication::open(manifest::path("comics/large-page.cbz")).unwrap();
    let identity = opened.publication().identity.clone();
    let path = folder.path().join("library.sqlite");
    {
        let store = ProgressStore::open(&path).unwrap();
        assert_eq!(store.read(&identity).unwrap(), None);
        let record = ReadingProgress::new(
            identity.clone(),
            ReadingPosition::page(0, 1),
            Timestamp(1_760_000_000),
        );
        store.write(&record).unwrap();
    }
    let reopened = ProgressStore::open(&path).unwrap();
    let back = reopened.read(&identity).unwrap().unwrap();
    assert_eq!(back.position, ReadingPosition::page(0, 1));
    assert_eq!(back.updated_at, Timestamp(1_760_000_000));
    // Found by any identity component: the digest alone reaches it.
    let by_digest = storyarc_core::domain::PublicationIdentity {
        content_digest: identity.content_digest.clone(),
        ..Default::default()
    };
    assert!(reopened.read(&by_digest).unwrap().is_some());
    assert_eq!(reopened.recent(10).unwrap().len(), 1);
}
