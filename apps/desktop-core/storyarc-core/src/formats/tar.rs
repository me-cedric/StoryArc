//! A TAR reader, written here rather than delegated to libarchive. Mirrored from
//! StoryArcKit's `TarReader.swift`.
//!
//! TAR is 512-byte blocks with fixed-offset ASCII fields: there is no compression, no
//! central directory and no bit-packing. Reading it needs no C library, which is the same
//! reasoning ADR-0008 applies to ZIP.
//!
//! Every read goes through [`RandomAccessSource`], so indexing a CBT on an SMB share
//! fetches one 512-byte header per entry rather than the whole file.
//!
//! This parser runs on untrusted input. `SECURITY.md` names archive parsing as the largest
//! attack surface in the app, so no length taken from a header is used before it is checked
//! against the source, and every header's checksum is verified.

use std::sync::Arc;

use super::byte_reader::latin1;
use crate::io::{HeaderBounds, RandomAccessSource, SourceError};

/// One regular file inside a TAR archive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TarEntry {
    pub path: String,
    pub size: u64,
    /// Where the file's bytes start. TAR stores data uncompressed and contiguous, so this
    /// offset plus `size` is the whole read — no decode step at all.
    pub data_offset: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TarError {
    Malformed(&'static str),
    /// No `ustar` magic and no parsable header. The file is not a TAR.
    NotTar,
    Source(SourceError),
}

impl From<SourceError> for TarError {
    fn from(error: SourceError) -> Self {
        Self::Source(error)
    }
}

impl std::fmt::Display for TarError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Malformed(reason) => write!(f, "malformed TAR: {reason}"),
            Self::NotTar => f.write_str("not a TAR"),
            Self::Source(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for TarError {}

const BLOCK_SIZE: u64 = 512;
/// `ustar` sits at offset 257, which is why format sniffing has to read further into a
/// TAR than into any other container.
pub const MAGIC_OFFSET: usize = 257;
/// A long name or a pax record longer than this is not a name.
const MAX_NAME_RECORD: u64 = 8192;

pub struct TarReader {
    /// Regular files only, in archive order. Directories, symlinks and metadata blocks are
    /// consumed and dropped.
    entries: Vec<TarEntry>,
    source: Arc<dyn RandomAccessSource>,
}

impl TarReader {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, TarError> {
        let length = source.length();
        let mut found = Vec::new();
        let mut offset: u64 = 0;
        // Set by a GNU `L` block or a pax `path=` record, and consumed by the next entry.
        let mut pending_long_name: Option<String> = None;
        let mut saw_any_header = false;

        while offset + BLOCK_SIZE <= length {
            let block = source.read_exactly(offset, BLOCK_SIZE as usize)?;
            offset += BLOCK_SIZE;

            // Two consecutive zero blocks end an archive, but one is enough to stop: there
            // is nothing after it a reader could use.
            if block.iter().all(|&b| b == 0) {
                break;
            }

            if !Self::checksum_matches(&block) {
                // A bad checksum on the very first block means this was never a TAR. Later
                // on it means the archive is damaged, and `publication-formats` requires
                // returning what was readable.
                if !saw_any_header {
                    return Err(TarError::NotTar);
                }
                break;
            }
            saw_any_header = true;

            let size = Self::size_of(&block)?;
            let data_offset = offset;

            // Checked *before* any arithmetic uses it. A GNU base-256 field can carry a size
            // within 512 of u64::MAX, and the block padding below would wrap on it.
            if !HeaderBounds::span(data_offset, size, length) {
                // The header claims more bytes than the file holds. Stop rather than
                // trusting the next offset, which is now meaningless.
                break;
            }

            // Entry data is padded to a whole number of blocks. Safe now: `size` is no
            // larger than what remains of a real file.
            offset += size.div_ceil(BLOCK_SIZE) * BLOCK_SIZE;

            match block[156] {
                // 'L': GNU long name; this block's data names the next entry.
                0x4C => {
                    let raw =
                        source.read_exactly(data_offset, size.min(MAX_NAME_RECORD) as usize)?;
                    pending_long_name = Some(Self::trimmed_string(&raw));
                }
                // 'x', 'g': pax extended header.
                0x78 | 0x67 => {
                    let raw =
                        source.read_exactly(data_offset, size.min(MAX_NAME_RECORD) as usize)?;
                    pending_long_name = Self::pax_path(&raw).or(pending_long_name);
                }
                // '0' or NUL: a regular file.
                0x30 | 0x00 => {
                    let path = pending_long_name
                        .take()
                        .unwrap_or_else(|| Self::path_of(&block));
                    if !path.is_empty() && !path.ends_with('/') {
                        found.push(TarEntry {
                            path,
                            size,
                            data_offset,
                        });
                    }
                }
                // Directories, symlinks, devices, FIFOs. Not pages.
                _ => pending_long_name = None,
            }
        }

        if !saw_any_header {
            return Err(TarError::NotTar);
        }
        Ok(Self {
            entries: found,
            source,
        })
    }

    pub fn entries(&self) -> &[TarEntry] {
        &self.entries
    }

    /// A whole entry. No decompression: TAR stores bytes verbatim.
    pub fn data(&self, entry: &TarEntry) -> Result<Vec<u8>, TarError> {
        if !HeaderBounds::span(entry.data_offset, entry.size, self.source.length()) {
            return Err(TarError::Malformed("entry lies outside the source"));
        }
        Ok(self
            .source
            .read_exactly(entry.data_offset, entry.size as usize)?)
    }

    /// The header checksum, treating its own eight bytes as spaces.
    ///
    /// Historic writers disagreed on whether the bytes are signed, so both sums are
    /// accepted. This is the only integrity check TAR offers, and it is what stops a random
    /// 512 bytes from being read as an entry.
    fn checksum_matches(block: &[u8]) -> bool {
        if block.len() != BLOCK_SIZE as usize {
            return false;
        }
        let Ok(declared) = Self::octal(&block[148..156]) else {
            return false;
        };
        let mut unsigned: i64 = 0;
        let mut signed: i64 = 0;
        for (index, &byte) in block.iter().enumerate() {
            if (148..156).contains(&index) {
                unsigned += 0x20;
                signed += 0x20;
            } else {
                unsigned += i64::from(byte);
                signed += i64::from(byte as i8);
            }
        }
        let declared = i64::try_from(declared).unwrap_or(-1);
        declared == unsigned || declared == signed
    }

    /// USTAR splits long paths across a 155-byte prefix and a 100-byte name.
    fn path_of(block: &[u8]) -> String {
        let name = Self::trimmed_string(&block[0..100]);
        let is_ustar = &block[MAGIC_OFFSET..MAGIC_OFFSET + 5] == b"ustar";
        if !is_ustar {
            return name;
        }
        let prefix = Self::trimmed_string(&block[345..500]);
        if prefix.is_empty() {
            name
        } else {
            format!("{prefix}/{name}")
        }
    }

    fn size_of(block: &[u8]) -> Result<u64, TarError> {
        let field = &block[124..136];
        // GNU base-256: the high bit of the first byte marks a big-endian integer instead
        // of ASCII octal, for sizes that will not fit in 11 octal digits.
        if field[0] & 0x80 != 0 {
            let mut value = u64::from(field[0] & 0x7F);
            for &byte in &field[1..] {
                if value >= u64::MAX >> 8 {
                    return Err(TarError::Malformed("size overflows"));
                }
                value = value << 8 | u64::from(byte);
            }
            return Ok(value);
        }
        Self::octal(field)
    }

    fn octal(bytes: &[u8]) -> Result<u64, TarError> {
        let mut value: u64 = 0;
        let mut saw_digit = false;
        for &byte in bytes {
            if byte == 0 || byte == 0x20 {
                // Trailing NUL or space terminates the field; leading ones are padding.
                if saw_digit {
                    break;
                }
                continue;
            }
            if !(0x30..=0x37).contains(&byte) {
                return Err(TarError::Malformed("not an octal field"));
            }
            if value >= u64::MAX >> 3 {
                return Err(TarError::Malformed("octal field overflows"));
            }
            value = value << 3 | u64::from(byte - 0x30);
            saw_digit = true;
        }
        Ok(value)
    }

    /// A NUL-terminated fixed-width field. UTF-8 where possible, ISO-8859-1 otherwise, so
    /// no byte sequence costs us an entry name.
    fn trimmed_string(bytes: &[u8]) -> String {
        let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
        let raw = &bytes[..end];
        std::str::from_utf8(raw).map_or_else(|_| latin1(raw), str::to_owned)
    }

    /// The `path=` record from a pax extended header. Records are `<length> <key>=<value>\n`,
    /// with the length counting the whole record.
    fn pax_path(data: &[u8]) -> Option<String> {
        let text = std::str::from_utf8(data).ok()?;
        let mut rest = text;
        while let Some(space) = rest.find(' ') {
            let declared: usize = rest[..space].parse().ok()?;
            if declared == 0 || declared > rest.len() || !rest.is_char_boundary(declared) {
                return None;
            }
            let record = &rest[..declared];
            rest = &rest[declared..];
            let body = record[space + 1..].trim_end_matches('\n');
            if let Some(path) = body.strip_prefix("path=") {
                return Some(path.to_owned());
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemorySource;

    fn source(bytes: Vec<u8>) -> Arc<dyn RandomAccessSource> {
        Arc::new(MemorySource::new(bytes))
    }

    /// The checksum a real TAR writer would have written for this header.
    fn write_checksum(header: &mut [u8; 512]) {
        header[148..156].fill(0x20);
        let sum: u32 = header.iter().map(|&b| u32::from(b)).sum();
        let field = format!("{sum:06o}\0 ");
        header[148..156].copy_from_slice(field.as_bytes());
    }

    #[test]
    fn a_block_whose_checksum_does_not_match_is_not_a_header() {
        let mut bytes = vec![0u8; 1024];
        bytes[0..9].copy_from_slice(b"page1.png");
        bytes[257..262].copy_from_slice(b"ustar");
        // Deliberately no checksum field. A parser that trusts the magic alone would read
        // a 512-byte block of zeros as an entry.
        assert_eq!(TarReader::open(source(bytes)).err(), Some(TarError::NotTar));
    }

    #[test]
    fn a_header_claiming_more_than_the_file_holds_yields_no_entry() {
        let mut header = [0u8; 512];
        header[0..9].copy_from_slice(b"page1.png");
        header[257..262].copy_from_slice(b"ustar");
        header[156] = 0x30;
        // 8 GB of data behind a 512-byte file.
        header[124..135].copy_from_slice(b"77777777777");
        write_checksum(&mut header);
        let reader = TarReader::open(source(header.to_vec())).unwrap();
        // The header parses, so this is not "not a TAR", but the entry cannot be surfaced.
        assert!(reader.entries().is_empty());
    }

    #[test]
    fn an_empty_source_is_not_an_empty_archive() {
        assert_eq!(
            TarReader::open(source(Vec::new())).err(),
            Some(TarError::NotTar)
        );
    }

    #[test]
    fn a_base_256_size_near_the_ceiling_does_not_wrap() {
        let mut header = [0u8; 512];
        header[0..9].copy_from_slice(b"page1.png");
        header[257..262].copy_from_slice(b"ustar");
        header[156] = 0x30;
        header[124] = 0xFF;
        header[125..136].fill(0xFF);
        write_checksum(&mut header);
        // Refused as an overflow or dropped as out of range; never an entry, never a panic.
        match TarReader::open(source(header.to_vec())) {
            Ok(reader) => assert!(reader.entries().is_empty()),
            Err(error) => assert_eq!(error, TarError::Malformed("size overflows")),
        }
    }

    #[test]
    fn a_pax_path_record_is_read() {
        assert_eq!(
            TarReader::pax_path(b"30 path=chapter/very-long.png\n"),
            Some("chapter/very-long.png".to_owned())
        );
        assert_eq!(TarReader::pax_path(b"5 x=y\n"), None);
        assert_eq!(TarReader::pax_path(b"999 path=a\n"), None);
    }
}
