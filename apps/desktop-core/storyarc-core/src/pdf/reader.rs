//! `Read + Seek` over a [`RandomAccessSource`], the shape PDFium's file callbacks take.

use std::io::{self, Read, Seek, SeekFrom};
use std::sync::Arc;

use crate::io::RandomAccessSource;

/// A cursor over a source. PDFium seeks to each object it needs and reads it, so a
/// source that answers ranged reads serves a document without being read whole.
pub struct SourceReader {
    source: Arc<dyn RandomAccessSource>,
    position: u64,
}

impl SourceReader {
    pub fn new(source: Arc<dyn RandomAccessSource>) -> Self {
        Self {
            source,
            position: 0,
        }
    }
}

impl Read for SourceReader {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let length = self.source.length();
        if self.position >= length || buf.is_empty() {
            return Ok(0);
        }
        let remaining = usize::try_from(length - self.position).unwrap_or(usize::MAX);
        let count = buf.len().min(remaining);
        let bytes = self
            .source
            .read(self.position, count)
            .map_err(|e| io::Error::other(e.to_string()))?;
        let read = bytes.len().min(count);
        buf[..read].copy_from_slice(&bytes[..read]);
        self.position += read as u64;
        Ok(read)
    }
}

impl Seek for SourceReader {
    fn seek(&mut self, target: SeekFrom) -> io::Result<u64> {
        let length = self.source.length();
        let next = match target {
            SeekFrom::Start(offset) => Some(offset),
            SeekFrom::End(delta) => length.checked_add_signed(delta),
            SeekFrom::Current(delta) => self.position.checked_add_signed(delta),
        };
        let Some(next) = next else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "seek before the start of the source",
            ));
        };
        self.position = next;
        Ok(next)
    }
}
