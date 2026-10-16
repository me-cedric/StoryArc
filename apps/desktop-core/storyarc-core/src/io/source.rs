//! Bytes that can be read at an arbitrary offset.
//!
//! The abstraction ADR-0008 is built on, mirrored from StoryArcKit's
//! `RandomAccessSource.swift`. Everything above it — the ZIP reader, the page decoder, the
//! reader windows — is unaware of whether the bytes came from a local file, an SMB share or
//! an HTTP range request. That is what makes streaming stop being a special case.
//!
//! Synchronous on purpose, where the Swift one is `async`: the core has no async runtime
//! yet (design.md, Open Question 5), and a blocking read behind a trait object is what both
//! a GTK worker thread and a C# `Task.Run` call expect. Retrofitting async later means
//! changing one trait, not every parser.

use std::fs::File;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

/// A read that could not be served.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SourceError {
    /// A read reached past the end of the source. Always a bug in the caller or a lie in
    /// the file being parsed, never a normal condition.
    OutOfBounds {
        offset: u64,
        count: usize,
        length: u64,
    },
    /// The source could not deliver the bytes it was asked for. Carries the OS or
    /// transport message so a bug report can say which.
    Unreadable(String),
    /// The read was abandoned because its [`CancelToken`] fired. Not a failure of the
    /// file: a caller that sees this stops rather than reporting damage.
    Cancelled,
}

impl std::fmt::Display for SourceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::OutOfBounds {
                offset,
                count,
                length,
            } => write!(
                f,
                "read of {count} bytes at {offset} is outside a source of {length} bytes"
            ),
            Self::Unreadable(message) => write!(f, "source unreadable: {message}"),
            Self::Cancelled => f.write_str("read cancelled"),
        }
    }
}

impl std::error::Error for SourceError {}

/// Range checks for numbers that came out of an untrusted archive header.
///
/// Every value taken from a header is checked here at the point it is parsed, and the
/// checks themselves report overflow rather than performing it: both operands are
/// attacker-chosen, and their sum is exactly what would wrap. Rust's release builds wrap
/// silently where Swift traps, and a wrapped offset that passes a `<= length` test is a
/// read of the wrong bytes rather than a crash — which is worse, because nothing says so.
pub struct HeaderBounds;

impl HeaderBounds {
    /// Whether `count` bytes starting at `offset` really are inside `length` bytes.
    pub fn span(offset: u64, count: u64, length: u64) -> bool {
        offset.checked_add(count).is_some_and(|end| end <= length)
    }

    /// Whether a header's offset or length names a position inside `length` bytes.
    ///
    /// An uncompressed size is deliberately *not* checked with this: compression means a
    /// value larger than the file is honest there. Everything else — a local header offset,
    /// a central directory offset, a compressed size — is a lie when it is.
    pub fn position(value: u64, length: u64) -> bool {
        value <= length
    }
}

/// Bytes that can be read at an arbitrary offset.
pub trait RandomAccessSource: Send + Sync {
    /// Total length in bytes. Known up front for every source StoryArc targets — SMB
    /// reports it in a file-info response, HTTP in `Content-Length`.
    fn length(&self) -> u64;

    /// Reads up to `count` bytes from `offset`. Returns fewer only at the end of the
    /// source; never more.
    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError>;

    /// Reads exactly `count` bytes, or fails. Parsers want this: a short read
    /// mid-structure means the file is malformed, not that the caller should retry.
    fn read_exactly(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        let length = self.length();
        if !HeaderBounds::span(offset, count as u64, length) {
            return Err(SourceError::OutOfBounds {
                offset,
                count,
                length,
            });
        }
        let data = self.read(offset, count)?;
        if data.len() != count {
            return Err(SourceError::Unreadable(format!(
                "short read: {} of {count} bytes at {offset}",
                data.len()
            )));
        }
        Ok(data)
    }

    /// Reads the last `count` bytes, or the whole source when it is shorter, and says
    /// where they started.
    fn read_tail(&self, count: usize) -> Result<(Vec<u8>, u64), SourceError> {
        let length = self.length();
        let size = (count as u64).min(length);
        let offset = length - size;
        // `size <= count`, so the narrowing is exact.
        Ok((self.read_exactly(offset, size as usize)?, offset))
    }
}

/// A local file, read through positional reads so the handle needs no lock.
pub struct FileSource {
    file: File,
    length: u64,
}

impl FileSource {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, SourceError> {
        let path = path.as_ref();
        let file =
            File::open(path).map_err(|error| SourceError::Unreadable(describe(path, &error)))?;
        let length = file
            .metadata()
            .map_err(|error| SourceError::Unreadable(describe(path, &error)))?
            .len();
        Ok(Self { file, length })
    }
}

fn describe(path: &Path, error: &std::io::Error) -> String {
    format!("{}: {error}", path.display())
}

impl RandomAccessSource for FileSource {
    fn length(&self) -> u64 {
        self.length
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        let mut buffer = vec![0; count];
        let mut filled = 0;
        while filled < count {
            let got = read_at(&self.file, offset + filled as u64, &mut buffer[filled..])
                .map_err(|error| SourceError::Unreadable(error.to_string()))?;
            if got == 0 {
                break;
            }
            filled += got;
        }
        buffer.truncate(filled);
        Ok(buffer)
    }
}

/// One positional read, which both platforms offer under different names.
#[cfg(unix)]
fn read_at(file: &File, offset: u64, buffer: &mut [u8]) -> std::io::Result<usize> {
    std::os::unix::fs::FileExt::read_at(file, buffer, offset)
}

#[cfg(windows)]
fn read_at(file: &File, offset: u64, buffer: &mut [u8]) -> std::io::Result<usize> {
    std::os::windows::fs::FileExt::seek_read(file, buffer, offset)
}

/// A source backed by bytes already in memory. Used by tests, and by the sparse cache
/// once a range has been fetched.
pub struct MemorySource {
    bytes: Vec<u8>,
}

impl MemorySource {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        Self {
            bytes: bytes.into(),
        }
    }
}

impl RandomAccessSource for MemorySource {
    fn length(&self) -> u64 {
        self.bytes.len() as u64
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        let length = self.length();
        if offset > length {
            return Err(SourceError::OutOfBounds {
                offset,
                count,
                length,
            });
        }
        let start = offset as usize;
        let end = start.saturating_add(count).min(self.bytes.len());
        Ok(self.bytes[start..end].to_vec())
    }
}

/// A flag a caller raises to abandon the reads in flight behind it.
///
/// Cheap to clone: every clone is the same flag. The C ABI hands one of these to C# as
/// `storyarc_cancel`, and a GTK window keeps one per open publication.
#[derive(Debug, Clone, Default)]
pub struct CancelToken {
    cancelled: Arc<AtomicBool>,
}

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    /// Raises the flag. Idempotent, and never lowered again: a cancelled operation stays
    /// cancelled, which is what makes the answer safe to read from any thread.
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    /// `Err(Cancelled)` once the flag is up. The one check every read makes.
    pub fn check(&self) -> Result<(), SourceError> {
        if self.is_cancelled() {
            Err(SourceError::Cancelled)
        } else {
            Ok(())
        }
    }
}

/// A source whose reads stop once a token fires.
///
/// Checked before *and* after the inner read: before, so a cancelled scan issues no more
/// IO; after, so a token raised while a slow transport was busy is honoured on the read it
/// interrupted rather than on the next one — "cancel mid-read" means the caller never sees
/// the bytes of a read it gave up on.
pub struct Cancellable<S> {
    inner: S,
    token: CancelToken,
}

impl<S: RandomAccessSource> Cancellable<S> {
    pub fn new(inner: S, token: CancelToken) -> Self {
        Self { inner, token }
    }
}

impl<S: RandomAccessSource> RandomAccessSource for Cancellable<S> {
    fn length(&self) -> u64 {
        self.inner.length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        self.token.check()?;
        let data = self.inner.read(offset, count)?;
        self.token.check()?;
        Ok(data)
    }
}

impl<S: RandomAccessSource + ?Sized> RandomAccessSource for Arc<S> {
    fn length(&self) -> u64 {
        (**self).length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        (**self).read(offset, count)
    }
}

impl<S: RandomAccessSource + ?Sized> RandomAccessSource for Box<S> {
    fn length(&self) -> u64 {
        (**self).length()
    }

    fn read(&self, offset: u64, count: usize) -> Result<Vec<u8>, SourceError> {
        (**self).read(offset, count)
    }
}
