//! Task 4.3 of `desktop-clients`: the Readium Web Publication Manifest and the positions
//! list the desktop EPUB bundle takes, built by the core for every corpus book.
//!
//! The positions must be the numbers iOS and Android show for the same book. Both phones
//! take them from Readium's `EPUBPositionsService`: one reading-order entry yields
//! `ceil(compressed entry size / 1024)` positions, never fewer than one, and a fixed-layout
//! book yields one position per entry. The counts below were read from each fixture's ZIP
//! central directory by hand, so the test fails when the rule or the reader drifts, and
//! the rule is also recomputed from the ZIP so a new fixture is covered before its count
//! is written here.

use std::sync::Arc;

use serde_json::Value;
use storyarc_core::epub::WebPublication;
use storyarc_core::formats::ZipReader;
use storyarc_core::io::FileSource;

mod corpus {
    #[allow(dead_code)]
    pub mod manifest;
}

/// Every corpus book that opens, with the position count of each reading-order entry.
const BOOKS: &[(&str, &[u64])] = &[
    ("ebooks/fixture.epub", &[1, 1]),
    ("ebooks/epub2.epub", &[1, 1]),
    ("ebooks/series.epub", &[1]),
    ("ebooks/one-sentence.epub", &[1]),
    ("ebooks/fixed-layout.epub", &[1, 1]),
    ("ebooks/spine-cover.epub", &[1, 1]),
    ("ebooks/declared-rtl.epub", &[1]),
];

const SELF_URL: &str = "storyarc://publication/manifest.json";

fn open(file: &str) -> WebPublication {
    let source = FileSource::open(corpus::manifest::path(file)).unwrap();
    WebPublication::open(Arc::new(source), SELF_URL).unwrap_or_else(|e| panic!("{file}: {e}"))
}

fn positions_of(file: &str) -> Vec<Value> {
    let json = open(file).positions_json();
    serde_json::from_str::<Value>(&json)
        .unwrap()
        .as_array()
        .cloned()
        .unwrap()
}

#[test]
fn every_corpus_book_has_the_positions_the_phones_show() {
    for (file, counts) in BOOKS {
        let publication = open(file);
        let manifest: Value = serde_json::from_str(&publication.manifest_json()).unwrap();
        let reading_order = manifest["readingOrder"].as_array().unwrap();
        assert_eq!(reading_order.len(), counts.len(), "{file}: reading order");

        // The rule, recomputed from the container: the compressed size of each spine entry.
        let source = FileSource::open(corpus::manifest::path(file)).unwrap();
        let zip = ZipReader::open(Arc::new(source)).unwrap();
        let fixed = manifest["metadata"]["layout"] == "fixed";
        let expected: Vec<u64> = reading_order
            .iter()
            .map(|link| {
                let entry = zip.entry(link["href"].as_str().unwrap()).unwrap();
                if fixed {
                    1
                } else {
                    entry.compressed_size.div_ceil(1024).max(1)
                }
            })
            .collect();
        assert_eq!(&expected, counts, "{file}: the rule over the ZIP");

        let positions = positions_of(file);
        let total: u64 = counts.iter().sum();
        assert_eq!(positions.len() as u64, total, "{file}: positions");
        let mut index = 0usize;
        for (link, count) in reading_order.iter().zip(counts.iter()) {
            for page in 0..*count {
                let locator = &positions[index];
                let locations = &locator["locations"];
                assert_eq!(locator["href"], link["href"], "{file}: href at {index}");
                assert_eq!(locator["type"], link["type"], "{file}: type at {index}");
                assert_eq!(locations["position"], index as u64 + 1, "{file}: position");
                assert_eq!(
                    locations["progression"].as_f64().unwrap(),
                    page as f64 / *count as f64,
                    "{file}: progression at {index}"
                );
                assert_eq!(
                    locations["totalProgression"].as_f64().unwrap(),
                    index as f64 / total as f64,
                    "{file}: total progression at {index}"
                );
                index += 1;
            }
        }
    }
}

#[test]
fn the_manifest_has_what_the_bundle_reads() {
    let manifest: Value =
        serde_json::from_str(&open("ebooks/fixture.epub").manifest_json()).unwrap();
    assert_eq!(
        manifest["@context"],
        "https://readium.org/webpub-manifest/context.jsonld"
    );
    let metadata = &manifest["metadata"];
    assert_eq!(metadata["@type"], "http://schema.org/Book");
    assert_eq!(metadata["title"], "Fixture Publication");
    assert_eq!(metadata["author"], "StoryArc Fixtures");
    assert_eq!(metadata["identifier"], "urn:uuid:storyarc-fixture-0001");
    assert_eq!(metadata["language"], serde_json::json!(["en"]));
    assert_eq!(metadata["layout"], "reflowable");
    assert_eq!(metadata["readingProgression"], "auto");
    assert_eq!(manifest["links"][0]["rel"], "self");
    assert_eq!(manifest["links"][0]["href"], SELF_URL);
    assert_eq!(manifest["links"][0]["type"], "application/webpub+json");

    let reading_order = manifest["readingOrder"].as_array().unwrap();
    assert_eq!(reading_order[0]["href"], "OEBPS/ch1.xhtml");
    assert_eq!(reading_order[0]["type"], "application/xhtml+xml");
    assert_eq!(reading_order[0]["title"], "Chapter One");
    assert_eq!(reading_order[1]["title"], "Chapter Two");

    let toc = manifest["toc"].as_array().unwrap();
    assert_eq!(toc.len(), 2);
    assert_eq!(toc[1]["href"], "OEBPS/ch2.xhtml");
    assert_eq!(toc[1]["title"], "Chapter Two");

    // The cover and every other non-spine item, so the host can serve what a page asks for.
    let resources = manifest["resources"].as_array().unwrap();
    let cover = resources.iter().find(|r| r["rel"] == "cover").unwrap();
    assert_eq!(cover["href"], "OEBPS/cover.png");
    assert_eq!(cover["type"], "image/png");
    assert!(
        resources.iter().all(|r| r["href"] != "OEBPS/ch1.xhtml"),
        "a spine item is not a resource"
    );
}

#[test]
fn layout_and_direction_come_from_the_package() {
    let fixed: Value =
        serde_json::from_str(&open("ebooks/fixed-layout.epub").manifest_json()).unwrap();
    assert_eq!(fixed["metadata"]["layout"], "fixed");
    let rtl: Value =
        serde_json::from_str(&open("ebooks/declared-rtl.epub").manifest_json()).unwrap();
    assert_eq!(rtl["metadata"]["readingProgression"], "rtl");
}

#[test]
fn a_resource_is_served_by_its_container_path() {
    let publication = open("ebooks/fixture.epub");
    let bytes = publication.resource("OEBPS/ch1.xhtml").unwrap();
    assert!(bytes.starts_with(b"<?xml") || bytes.starts_with(b"<html"));
    assert_eq!(
        publication.media_type("OEBPS/ch1.xhtml"),
        Some("application/xhtml+xml")
    );
    assert!(publication.resource("OEBPS/missing.xhtml").is_err());
}

#[test]
fn a_book_with_no_package_is_refused_by_name() {
    let source = FileSource::open(corpus::manifest::path("ebooks/no-package.epub")).unwrap();
    let error = WebPublication::open(Arc::new(source), SELF_URL)
        .err()
        .unwrap();
    assert_eq!(error.to_string(), "no package document");
}
