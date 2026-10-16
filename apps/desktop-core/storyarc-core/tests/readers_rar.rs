//! RAR reader and decoder tests over the shared corpus: the twin of iOS's `RarReaderTests`
//! and `RarDecoderTests`. The corpus harness asserts what the manifest records; this file
//! asserts the seam between our header reader and libarchive.

mod corpus {
    // Only the corpus path helper is used from this binary; the typed manifest belongs to
    // `tests/corpus.rs`, which is the one place the manifest's expectations are asserted.
    #[allow(dead_code)]
    pub mod manifest;
}

use std::sync::Arc;

use storyarc_core::formats::rar::RAR4_SIGNATURE;
use storyarc_core::formats::{DecodeError, RarDecoder, RarError, RarReader};
use storyarc_core::io::MemorySource;

/// The store fixture with its method byte flipped from store to LZ: the headers stay valid,
/// so this isolates the one case a decoder is for.
fn store_fixture_marked_compressed() -> Vec<u8> {
    let mut bytes = std::fs::read(corpus::manifest::path("comics/rar4-store.cbr")).unwrap();
    // Signature, then the 13-byte main header, then METHOD at offset 25 inside the file header.
    let method_offset = RAR4_SIGNATURE.len() + 13 + 25;
    assert_eq!(
        bytes[method_offset], 0x30,
        "expected the store method byte here"
    );
    bytes[method_offset] = 0x33;
    bytes
}

#[test]
fn a_compressed_entry_names_the_decoder_it_needs_rather_than_failing_vaguely() {
    let reader = RarReader::open(Arc::new(MemorySource::new(
        store_fixture_marked_compressed(),
    )))
    .unwrap();
    let entry = &reader.entries()[0];
    assert!(!entry.is_stored);
    assert_eq!(reader.data(entry).err(), Some(RarError::NeedsDecoder));
}

#[test]
fn an_isolated_entry_with_a_broken_crc_is_refused_as_a_decode_failure() {
    // The flip broke the header CRC, so libarchive refuses the entry. It is refused as a
    // decode failure, not as a container that needs a file.
    let reader = RarReader::open(Arc::new(MemorySource::new(
        store_fixture_marked_compressed(),
    )))
    .unwrap();
    let entry = &reader.entries()[0];
    let isolated = reader.isolated(entry).unwrap();
    assert!(matches!(
        RarDecoder::data_of_isolated(&entry.path, isolated),
        Err(DecodeError::Libarchive(_)
            | DecodeError::CannotOpen(_)
            | DecodeError::Truncated { .. })
    ));
}

#[test]
fn a_missing_entry_is_named_rather_than_returning_empty_data() {
    let path = corpus::manifest::path("comics/rar5-compressed.cbr");
    assert_eq!(
        RarDecoder::data_for_entry("nope.png", &path).err(),
        Some(DecodeError::EntryNotFound("nope.png".to_owned()))
    );
}

#[test]
fn a_file_that_is_not_a_rar_is_refused_at_open() {
    let path = corpus::manifest::path("comics/natural-sort.cbz");
    assert!(matches!(
        RarDecoder::entry_names(&path),
        Err(DecodeError::CannotOpen(_) | DecodeError::Libarchive(_))
    ));
}

#[test]
fn asking_for_nothing_does_no_work() {
    let path = corpus::manifest::path("comics/rar5-compressed.cbr");
    assert!(
        RarDecoder::data_for_entries(&Default::default(), &path)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn an_empty_buffer_cannot_be_opened() {
    assert_eq!(
        RarDecoder::data_of_isolated("x", Vec::new()).err(),
        Some(DecodeError::CannotOpen("empty archive buffer".to_owned()))
    );
}

#[test]
fn an_isolated_entry_outside_the_source_is_refused_before_any_read() {
    let reader = RarReader::open(Arc::new(MemorySource::new(
        std::fs::read(corpus::manifest::path("comics/rar5-store.cbr")).unwrap(),
    )))
    .unwrap();
    let mut entry = reader.entries()[0].clone();
    entry.packed_size = u64::MAX;
    assert_eq!(
        reader.isolated(&entry).err(),
        Some(RarError::Malformed("entry lies outside the source"))
    );
}
