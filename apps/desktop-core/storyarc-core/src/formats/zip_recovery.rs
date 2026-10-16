//! Rebuilding a ZIP's index when its central directory is gone.
//!
//! For an archive whose central directory is gone — a truncated download, a partial copy
//! off a failing disk. `publication-formats` requires opening whatever pages can be read
//! and reporting what was skipped, rather than refusing the publication, and ADR-0008 notes
//! that owning the reader is what makes this possible at all.
//!
//! It reads the archive **linearly**, which is inherent: recovery exists precisely because
//! there is no index to seek with. That is the one place this reader gives up the
//! ranged-read property, and it is why it is a separate entry point rather than a silent
//! fallback.
//!
//! Local headers are trusted here for sizes, which ADR-0008 otherwise forbids — because in
//! recovery there is nothing better. Where a header declares no size (a data descriptor was
//! used), the entry runs to the next signature.

use std::sync::Arc;

use super::byte_reader::ByteReader;
use super::zip::{LOCAL_HEADER_SIGNATURE, ZipEntry, ZipError, ZipReader};
use crate::io::{HeaderBounds, RandomAccessSource};

/// A comic has hundreds of entries. Tens of thousands is a crafted file.
const ENTRY_LIMIT: usize = 50_000;
/// Read in windows with an overlap, so a signature straddling a boundary is still seen whole.
const WINDOW: usize = 1 << 20;
const OVERLAP: usize = 4;

/// One local header: the entry it describes and where its data starts.
struct LocalEntry {
    entry: ZipEntry,
    data_offset: u64,
}

impl ZipReader {
    /// Rebuilds an index by scanning for local file headers.
    pub fn recovering(source: Arc<dyn RandomAccessSource>) -> Result<Self, ZipError> {
        let length = source.length();
        let mut found: Vec<ZipEntry> = Vec::new();
        let mut offset: u64 = 0;
        let mut pending: Option<LocalEntry> = None;

        while offset < length && found.len() < ENTRY_LIMIT {
            let count = (WINDOW as u64).min(length - offset) as usize;
            let bytes = source.read_exactly(offset, count)?;
            let mut index = 0;

            while index + 4 <= bytes.len() {
                if bytes[index] != 0x50 || bytes[index + 1] != 0x4B {
                    index += 1;
                    continue;
                }
                let at = offset + index as u64;
                let third = bytes[index + 2];
                let fourth = bytes[index + 3];

                // A central-directory or EOCD signature ends the entry region.
                if third == 0x01 || third == 0x05 || third == 0x06 {
                    if let Some(waiting) = pending.take() {
                        Self::append(&mut found, waiting, Some(at), length);
                    }
                    return Self::recovered(found, source);
                }

                if third != 0x03 || fourth != 0x04 {
                    index += 1;
                    continue;
                }

                // A previous entry with no declared size ends where this one starts.
                if let Some(waiting) = pending.take() {
                    Self::append(&mut found, waiting, Some(at), length);
                }

                match Self::local_entry(at, source.as_ref()) {
                    Ok(parsed) => {
                        if parsed.entry.compressed_size > 0 {
                            Self::append(&mut found, parsed, None, length);
                        } else {
                            // Size unknown until the next signature is found.
                            pending = Some(parsed);
                        }
                        index += 4;
                    }
                    Err(_) => index += 1,
                }
            }

            if length - offset <= count as u64 {
                break;
            }
            offset += (count - OVERLAP) as u64;
        }

        if let Some(waiting) = pending.take() {
            // The last entry runs to the end of what survived.
            Self::append(&mut found, waiting, Some(length), length);
        }
        Self::recovered(found, source)
    }

    fn recovered(
        entries: Vec<ZipEntry>,
        source: Arc<dyn RandomAccessSource>,
    ) -> Result<Self, ZipError> {
        if entries.is_empty() {
            return Err(ZipError::NoCentralDirectory);
        }
        Ok(Self {
            entries,
            is_recovered: true,
            has_archive_comment: false,
            source,
        })
    }

    /// Adds an entry, dropping it when its data does not fit in what survived.
    ///
    /// A truncated archive's final entry is the common case: its header is intact and its
    /// bytes are not. Dropping it is what makes "opened 10, skipped 2" truthful rather than
    /// a promise the reader cannot keep.
    fn append(found: &mut Vec<ZipEntry>, parsed: LocalEntry, end: Option<u64>, length: u64) {
        let mut entry = parsed.entry;
        if let Some(end) = end {
            let Some(available) = end.checked_sub(parsed.data_offset).filter(|&n| n > 0) else {
                return;
            };
            // The uncompressed size stays as declared, usually zero: unknown without
            // inflating. Zero means "ask the decoder", and callers treat a zero-length page
            // as skipped, so it must not be used as a page size.
            entry.compressed_size = available;
        }
        if !HeaderBounds::span(parsed.data_offset, entry.compressed_size, length) {
            return;
        }
        found.push(entry);
    }

    /// Parses one local file header. Returns the entry and where its data starts.
    fn local_entry(offset: u64, source: &dyn RandomAccessSource) -> Result<LocalEntry, ZipError> {
        let length = source.length();
        let header = source.read_exactly(offset, (length - offset).min(30) as usize)?;
        let mut reader = ByteReader::new(&header);
        if reader.u32()? != LOCAL_HEADER_SIGNATURE {
            return Err(ZipError::Malformed("not a local header"));
        }
        reader.skip(2)?; // version needed
        let flags = reader.u16()?;
        let method = reader.u16()?;
        reader.skip(2 + 2 + 4)?; // time, date, crc
        let compressed = u64::from(reader.u32()?);
        let uncompressed = u64::from(reader.u32()?);
        let name_length = usize::from(reader.u16()?);
        let extra_length = u64::from(reader.u16()?);

        if name_length == 0 || name_length > 4096 {
            return Err(ZipError::Malformed("implausible name length"));
        }
        let name_data = source.read_exactly(offset + 30, name_length)?;
        let path = ByteReader::new(&name_data).string(name_length, flags & 0x0800 != 0)?;

        let data_offset = offset + 30 + name_length as u64 + extra_length;
        if data_offset > length {
            return Err(ZipError::Malformed("local header runs past the source"));
        }
        Ok(LocalEntry {
            entry: ZipEntry {
                path,
                compressed_size: compressed,
                uncompressed_size: uncompressed,
                local_header_offset: offset,
                compression_method: method,
                is_encrypted: flags & 0x0001 != 0,
            },
            data_offset,
        })
    }
}
