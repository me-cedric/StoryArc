//! Reader-level tests over the shared corpus: the properties each container reader has
//! that no single manifest field records. The twins of iOS's `ZipReaderTests`,
//! `TarReaderTests` and `RarReaderTests`.

mod corpus {
    pub mod manifest;
}

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use storyarc_core::formats::{ZipError, ZipReader};
use storyarc_core::io::{FileSource, MemorySource, RandomAccessSource, SourceError};

/// Counts what a reader actually touches, so "ranged reads" can be asserted rather than
/// asserted-about.
struct ReadCounter {
    inner: Box<dyn RandomAccessSource>,
    reads: AtomicUsize,
    bytes: AtomicUsize,
}

impl ReadCounter {
    fn new(inner: impl RandomAccessSource + 'static) -> Self {
        Self {
            inner: Box::new(inner),
            reads: AtomicUsize::new(0),
            bytes: AtomicUsize::new(0),
        }
    }
}

impl RandomAccessSource for ReadCounter {
    fn length(&self) -> u64 {
        self.inner.length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        let data = self.inner.read(offset, count)?;
        self.reads.fetch_add(1, Ordering::SeqCst);
        self.bytes.fetch_add(data.len(), Ordering::SeqCst);
        Ok(data)
    }
}

fn comic(name: &str) -> FileSource {
    FileSource::open(corpus::manifest::path(&format!("comics/{name}"))).expect("open fixture")
}

mod zip {
    use super::*;

    const PNG: [u8; 4] = [0x89, 0x50, 0x4E, 0x47];

    #[test]
    fn deflate_entries_inflate_to_their_recorded_size() {
        for name in [
            "natural-sort.cbz",
            "zip64.cbz",
            "archive-comment.cbz",
            "data-descriptor.cbz",
        ] {
            let zip = ZipReader::open(Arc::new(comic(name))).unwrap();
            let entry = zip
                .entries()
                .iter()
                .find(|e| e.path.ends_with(".png"))
                .unwrap();
            assert!(entry.is_deflated(), "{name}: expected DEFLATE");
            let data = zip.data(entry).unwrap();
            assert_eq!(data.len() as u64, entry.uncompressed_size, "{name}");
            assert_eq!(&data[..4], &PNG, "{name}: not a PNG, inflate produced junk");
        }
    }

    #[test]
    fn stored_entries_are_returned_as_is() {
        let zip = ZipReader::open(Arc::new(comic("stored-entries.cbz"))).unwrap();
        let entry = &zip.entries()[0];
        assert!(entry.is_stored());
        let data = zip.data(entry).unwrap();
        assert_eq!(data.len() as u64, entry.uncompressed_size);
        assert_eq!(&data[..4], &PNG);
    }

    #[test]
    fn zip64_extended_information_is_parsed() {
        let zip = ZipReader::open(Arc::new(comic("zip64.cbz"))).unwrap();
        assert_eq!(zip.entries().len(), 3);
        for entry in zip.entries() {
            assert!(entry.uncompressed_size > 0);
        }
    }

    #[test]
    fn an_archive_comment_does_not_hide_the_eocd() {
        // The EOCD sits hundreds of bytes from the end of this fixture. A reader that looks
        // at a fixed tail offset instead of scanning for the signature fails here.
        let zip = ZipReader::open(Arc::new(comic("archive-comment.cbz"))).unwrap();
        assert!(zip.has_archive_comment());
        assert_eq!(zip.entries().len(), 3);
    }

    #[test]
    fn with_a_data_descriptor_the_central_directory_is_the_authority() {
        // Local headers in this fixture carry zero sizes and general-purpose bit 3. A reader
        // that trusts the local header reads zero bytes.
        let zip = ZipReader::open(Arc::new(comic("data-descriptor.cbz"))).unwrap();
        for entry in zip.entries().iter().filter(|e| e.path.ends_with(".png")) {
            assert!(entry.compressed_size > 0, "central directory size unused");
            assert_eq!(
                zip.data(entry).unwrap().len() as u64,
                entry.uncompressed_size
            );
        }
    }

    #[test]
    fn reading_one_page_touches_a_fraction_of_the_archive() {
        // The claim ADR-0008 rests on, measured. This fixture is small, so the interesting
        // number is the *shape*: a bounded tail probe plus one entry, never a full read.
        let counter = Arc::new(ReadCounter::new(comic("natural-sort.cbz")));
        let zip = ZipReader::open(Arc::clone(&counter) as Arc<dyn RandomAccessSource>).unwrap();
        zip.data(&zip.entries()[0]).unwrap();
        // Tail probe, local header probe, entry data. The central directory came out of the
        // tail read, which is the common case for a comic.
        let reads = counter.reads.load(Ordering::SeqCst);
        assert!(
            reads <= 4,
            "expected a handful of ranged reads, got {reads}"
        );
    }

    #[test]
    fn a_truncated_archive_has_no_findable_central_directory() {
        assert_eq!(
            ZipReader::open(Arc::new(comic("truncated.cbz"))).err(),
            Some(ZipError::NoCentralDirectory)
        );
    }

    #[test]
    fn reads_are_bounds_checked_against_the_source_not_a_header() {
        let source = MemorySource::new(vec![0; 100]);
        assert_eq!(
            source.read_exactly(90, 20).err(),
            Some(SourceError::OutOfBounds {
                offset: 90,
                count: 20,
                length: 100
            })
        );
    }

    #[test]
    fn a_central_directory_pointing_outside_the_file_is_refused() {
        // An EOCD whose central directory offset is past the end: a lie about the archive,
        // refused before any read is issued on the strength of it.
        let mut bytes = vec![0u8; 64];
        let eocd = [
            0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 1, 0, 1, 0, 46, 0, 0, 0, 0xFF, 0xFF, 0, 0, 0, 0,
        ];
        bytes.extend_from_slice(&eocd);
        assert_eq!(
            ZipReader::open(Arc::new(MemorySource::new(bytes))).err(),
            Some(ZipError::Malformed("central directory outside the source"))
        );
    }
}
