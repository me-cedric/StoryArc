//! Range and cancellation tests for the sources (task 1.4).

use std::sync::{Arc, Mutex};

use super::source::*;

fn temp_file(bytes: &[u8]) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "storyarc-source-{}-{}.bin",
        std::process::id(),
        bytes.len()
    ));
    std::fs::write(&path, bytes).unwrap();
    path
}

#[test]
fn a_file_source_reports_its_real_length_and_reads_at_an_offset() {
    let whole: Vec<u8> = (0..=255).collect();
    let path = temp_file(&whole);
    let source = FileSource::open(&path).unwrap();
    assert_eq!(source.length(), 256);
    assert_eq!(source.read(100, 16).unwrap(), &whole[100..116]);
    // Past the end returns what is there, never more.
    assert_eq!(source.read(250, 16).unwrap(), &whole[250..]);
    std::fs::remove_file(path).unwrap();
}

#[test]
fn a_missing_file_is_unreadable_by_name() {
    let path = std::env::temp_dir().join("storyarc-does-not-exist.cbz");
    let Err(error) = FileSource::open(&path) else {
        panic!("a missing file opened");
    };
    assert!(matches!(error, SourceError::Unreadable(ref m) if m.contains("does-not-exist")));
}

#[test]
fn a_tail_read_returns_the_last_bytes_and_their_offset() {
    let source = MemorySource::new((0..100).collect::<Vec<u8>>());
    let (data, offset) = source.read_tail(10).unwrap();
    assert_eq!(offset, 90);
    assert_eq!(data, (90..100).collect::<Vec<u8>>());
}

#[test]
fn a_tail_read_larger_than_the_source_returns_the_whole_source() {
    let source = MemorySource::new((0..10).collect::<Vec<u8>>());
    let (data, offset) = source.read_tail(500).unwrap();
    assert_eq!(offset, 0);
    assert_eq!(data.len(), 10);
}

#[test]
fn read_exactly_refuses_a_range_past_the_end_before_reading() {
    let source = MemorySource::new(vec![0; 100]);
    assert_eq!(
        source.read_exactly(90, 20).err(),
        Some(SourceError::OutOfBounds {
            offset: 90,
            count: 20,
            length: 100
        })
    );
    assert_eq!(source.read_exactly(90, 10).unwrap().len(), 10);
}

#[test]
fn a_memory_read_starting_past_the_end_is_out_of_bounds() {
    let source = MemorySource::new(vec![0; 4]);
    assert!(matches!(
        source.read(5, 1),
        Err(SourceError::OutOfBounds { offset: 5, .. })
    ));
    assert!(source.read(4, 1).unwrap().is_empty());
}

#[test]
fn header_bounds_report_overflow_instead_of_performing_it() {
    assert!(!HeaderBounds::span(u64::MAX - 1, 2, u64::MAX));
    assert!(HeaderBounds::span(10, 5, 15));
    assert!(!HeaderBounds::span(10, 6, 15));
    assert!(HeaderBounds::position(15, 15));
    assert!(!HeaderBounds::position(16, 15));
}

/// A source that cancels its own token during the read: the shape of a slow transport
/// whose caller gave up while the bytes were in flight.
struct CancelsDuringRead {
    inner: MemorySource,
    token: CancelToken,
    reads: Mutex<usize>,
}

impl RandomAccessSource for CancelsDuringRead {
    fn length(&self) -> u64 {
        self.inner.length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        *self.reads.lock().unwrap() += 1;
        let data = self.inner.read(offset, count)?;
        self.token.cancel();
        Ok(data)
    }
}

#[test]
fn a_cancel_mid_read_withholds_the_bytes_of_that_read() {
    let token = CancelToken::new();
    let inner = Arc::new(CancelsDuringRead {
        inner: MemorySource::new(vec![7; 64]),
        token: token.clone(),
        reads: Mutex::new(0),
    });
    let source = Cancellable::new(Arc::clone(&inner), token.clone());
    assert!(!token.is_cancelled());
    // The inner read completed, the token fired while it ran, and the caller never sees
    // the bytes it gave up on.
    assert_eq!(
        source.read_exactly(0, 16).err(),
        Some(SourceError::Cancelled)
    );
    assert!(token.is_cancelled());
    // Once cancelled, no further IO is issued at all.
    assert_eq!(source.read(16, 16).err(), Some(SourceError::Cancelled));
    assert_eq!(*inner.reads.lock().unwrap(), 1);
}

#[test]
fn a_cancelled_token_stops_the_next_read_before_any_io() {
    let token = CancelToken::new();
    let source = Cancellable::new(MemorySource::new(vec![1; 32]), token.clone());
    assert_eq!(source.read(0, 8).unwrap().len(), 8);
    token.cancel();
    assert_eq!(source.read(8, 8).err(), Some(SourceError::Cancelled));
    assert_eq!(source.read_tail(8).err(), Some(SourceError::Cancelled));
}

#[test]
fn every_clone_of_a_token_is_the_same_flag() {
    let token = CancelToken::new();
    let other = token.clone();
    other.cancel();
    assert!(token.is_cancelled());
    assert_eq!(token.check(), Err(SourceError::Cancelled));
}

#[test]
fn a_boxed_or_shared_source_reads_through() {
    let shared: Arc<dyn RandomAccessSource> = Arc::new(MemorySource::new(vec![3; 8]));
    assert_eq!(shared.length(), 8);
    assert_eq!(shared.read_exactly(2, 2).unwrap(), vec![3, 3]);
    let boxed: Box<dyn RandomAccessSource> = Box::new(MemorySource::new(vec![4; 8]));
    assert_eq!(boxed.read_tail(2).unwrap(), (vec![4, 4], 6));
}

#[test]
fn a_cancelled_zip_open_reports_the_cancellation_not_damage() {
    // The reader above the source sees `Cancelled` through its own error, so a caller
    // that gave up is never told the file was broken.
    let bytes = std::fs::read(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../packages/test-fixtures/comics/natural-sort.cbz"),
    )
    .unwrap();
    let token = CancelToken::new();
    token.cancel();
    let source: Arc<dyn RandomAccessSource> =
        Arc::new(Cancellable::new(MemorySource::new(bytes), token));
    assert_eq!(
        crate::formats::ZipReader::open(source).err(),
        Some(crate::formats::ZipError::Source(SourceError::Cancelled))
    );
}
