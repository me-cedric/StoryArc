//! Our own ZIP reader over a [`RandomAccessSource`] (ADR-0008), mirrored from
//! StoryArcKit's `ZipReader.swift`.
//!
//! Three reads get any single entry out of an arbitrarily large archive: the tail, the
//! central directory if it did not fit in the tail, then the entry itself. For a 400 MB
//! comic that is megabytes, not gigabytes — which is what makes the `network-share`
//! streaming requirement achievable.
//!
//! We parse the container; we do not implement compression. Inflate comes from
//! `miniz_oxide`, the pure-Rust DEFLATE the platform does not ship.

use std::sync::Arc;

use super::byte_reader::ByteReader;
use crate::io::{HeaderBounds, RandomAccessSource, SourceError};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ZipError {
    /// No End of Central Directory record found. Either not a ZIP, or truncated.
    NoCentralDirectory,
    Malformed(&'static str),
    /// General-purpose bit 0 is set. `publication-formats` requires StoryArc to say the
    /// archive is protected rather than prompt for a password.
    Encrypted,
    UnsupportedCompression(u16),
    InflateFailed,
    Source(SourceError),
}

impl From<SourceError> for ZipError {
    fn from(error: SourceError) -> Self {
        Self::Source(error)
    }
}

impl std::fmt::Display for ZipError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoCentralDirectory => f.write_str("no central directory"),
            Self::Malformed(reason) => write!(f, "malformed ZIP: {reason}"),
            Self::Encrypted => f.write_str("encrypted entry"),
            Self::UnsupportedCompression(method) => {
                write!(f, "unsupported compression method {method}")
            }
            Self::InflateFailed => f.write_str("inflate failed"),
            Self::Source(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for ZipError {}

/// One entry, as described by the central directory.
///
/// **The central directory is the only authority.** Local headers are read for their name
/// and extra-field lengths and never trusted for sizes — with a data descriptor they
/// legitimately contain zeros. ADR-0008's central rule.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ZipEntry {
    pub path: String,
    pub compressed_size: u64,
    pub uncompressed_size: u64,
    pub local_header_offset: u64,
    pub compression_method: u16,
    pub is_encrypted: bool,
}

impl ZipEntry {
    pub fn is_stored(&self) -> bool {
        self.compression_method == 0
    }

    pub fn is_deflated(&self) -> bool {
        self.compression_method == 8
    }
}

/// Reads a ZIP's index and individual entries with ranged reads.
pub struct ZipReader {
    pub(crate) entries: Vec<ZipEntry>,
    /// True when the index was rebuilt by scanning rather than read from a central
    /// directory. Sizes then come from local headers, which are less trustworthy — so a
    /// caller that cares can say "recovered" rather than pretending.
    pub(crate) is_recovered: bool,
    /// Whether the archive carries a comment. Kept because its presence is exactly what
    /// breaks a reader that assumes the EOCD is the last 22 bytes.
    pub(crate) has_archive_comment: bool,
    pub(crate) source: Arc<dyn RandomAccessSource>,
}

// Signatures, little-endian on disk.
pub(crate) const EOCD_SIGNATURE: u32 = 0x0605_4B50;
pub(crate) const ZIP64_LOCATOR_SIGNATURE: u32 = 0x0706_4B50;
pub(crate) const ZIP64_EOCD_SIGNATURE: u32 = 0x0606_4B50;
pub(crate) const CENTRAL_ENTRY_SIGNATURE: u32 = 0x0201_4B50;
pub(crate) const LOCAL_HEADER_SIGNATURE: u32 = 0x0403_4B50;

/// The EOCD is at most 22 bytes plus a comment of up to 65,535. Reading 64 KB covers the
/// overwhelming majority of real archives and usually contains the whole central directory
/// too, collapsing three reads into two.
pub(crate) const TAIL_PROBE_SIZE: usize = 64 * 1024;

/// A ceiling on one entry's inflated size. The size comes from the central directory,
/// which is attacker controlled, so a lying header cannot make us allocate the world.
pub(crate) const MAX_INFLATED_BYTES: usize = 512 * 1024 * 1024;

impl ZipReader {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, ZipError> {
        let (tail, tail_offset) = source.read_tail(TAIL_PROBE_SIZE + 22)?;
        let eocd_index =
            Self::last_index(EOCD_SIGNATURE, &tail).ok_or(ZipError::NoCentralDirectory)?;

        let mut reader = ByteReader::at(&tail, eocd_index);
        reader.u32()?; // signature
        reader.skip(2 + 2 + 2)?; // disk numbers, entries on this disk
        let entry_count16 = reader.u16()?;
        let cd_size32 = reader.u32()?;
        let cd_offset32 = reader.u32()?;
        let comment_length = reader.u16()?;

        let mut entry_count = u64::from(entry_count16);
        let mut cd_size = u64::from(cd_size32);
        let mut cd_offset = u64::from(cd_offset32);

        // Any sentinel means the real values live in the Zip64 record.
        let needs_zip64 =
            entry_count16 == 0xFFFF || cd_size32 == 0xFFFF_FFFF || cd_offset32 == 0xFFFF_FFFF;
        if needs_zip64 || Self::last_index(ZIP64_LOCATOR_SIGNATURE, &tail).is_some() {
            match Self::read_zip64(&tail, tail_offset, source.as_ref())? {
                Some(zip64) => {
                    entry_count = zip64.entry_count;
                    cd_size = zip64.size;
                    cd_offset = zip64.offset;
                }
                None if needs_zip64 => {
                    return Err(ZipError::Malformed(
                        "zip64 sentinel present but no zip64 record",
                    ));
                }
                None => {}
            }
        }

        if !HeaderBounds::span(cd_offset, cd_size, source.length()) {
            return Err(ZipError::Malformed("central directory outside the source"));
        }

        // If the tail already covers the central directory, slice it rather than issuing a
        // second read. Most comic archives land here.
        let directory: Vec<u8> = if cd_offset >= tail_offset {
            let start = (cd_offset - tail_offset) as usize;
            let end = start.saturating_add(cd_size as usize).min(tail.len());
            if start > end {
                return Err(ZipError::Malformed("central directory slice invalid"));
            }
            tail[start..end].to_vec()
        } else {
            source.read_exactly(cd_offset, cd_size as usize)?
        };

        let entries = Self::parse_central_directory(&directory, entry_count, source.length())?;
        Ok(Self {
            entries,
            is_recovered: false,
            has_archive_comment: comment_length > 0,
            source,
        })
    }

    pub fn entries(&self) -> &[ZipEntry] {
        &self.entries
    }

    pub fn is_recovered(&self) -> bool {
        self.is_recovered
    }

    pub fn has_archive_comment(&self) -> bool {
        self.has_archive_comment
    }

    pub fn entry(&self, path: &str) -> Option<&ZipEntry> {
        self.entries.iter().find(|entry| entry.path == path)
    }

    /// The uncompressed bytes of one entry.
    pub fn data(&self, entry: &ZipEntry) -> Result<Vec<u8>, ZipError> {
        if entry.is_encrypted {
            return Err(ZipError::Encrypted);
        }

        // The local header's own name and extra lengths tell us where the data starts. Its
        // size fields are ignored — see `ZipEntry`. The offset is range-checked where the
        // central directory is parsed; this is the check that the check held.
        let length = self.source.length();
        let available = length
            .checked_sub(entry.local_header_offset)
            .ok_or(ZipError::Malformed("local header outside the source"))?;
        let header_probe = self
            .source
            .read_exactly(entry.local_header_offset, available.min(30) as usize)?;
        let mut reader = ByteReader::new(&header_probe);
        if reader.u32()? != LOCAL_HEADER_SIGNATURE {
            return Err(ZipError::Malformed("local header signature missing"));
        }
        reader.skip(2 + 2 + 2 + 2 + 2 + 4 + 4 + 4)?; // version…sizes, all untrusted
        let name_length = u64::from(reader.u16()?);
        let extra_length = u64::from(reader.u16()?);

        let data_offset = entry.local_header_offset + 30 + name_length + extra_length;
        if !HeaderBounds::span(data_offset, entry.compressed_size, length) {
            return Err(ZipError::Malformed("entry data outside the source"));
        }

        let compressed = self
            .source
            .read_exactly(data_offset, entry.compressed_size as usize)?;

        if entry.is_stored() {
            return Ok(compressed);
        }
        if !entry.is_deflated() {
            return Err(ZipError::UnsupportedCompression(entry.compression_method));
        }
        Self::inflate(&compressed, entry.uncompressed_size)
    }

    /// Raw DEFLATE. We parse the container; we do not implement compression (ADR-0008).
    pub(crate) fn inflate(compressed: &[u8], expected_size: u64) -> Result<Vec<u8>, ZipError> {
        // Zero can mean two things. An entry that really is empty has no compressed bytes
        // either; an entry recovered from a local header with a data descriptor has bytes
        // and no declared size. Only the first is empty.
        if expected_size == 0 && compressed.is_empty() {
            return Ok(Vec::new());
        }
        // `expected_size` comes from the central directory, so it is attacker controlled.
        // Capped so a lying header cannot make us allocate the world; unknown (zero, from
        // recovery) means "up to the cap", and the decoder grows the buffer as it goes.
        let limit = if expected_size == 0 {
            MAX_INFLATED_BYTES
        } else {
            usize::try_from(expected_size)
                .unwrap_or(MAX_INFLATED_BYTES)
                .min(MAX_INFLATED_BYTES)
        };
        // An empty stream is a legitimate answer here: an empty entry still carries the
        // two-byte DEFLATE block that says so.
        miniz_oxide::inflate::decompress_to_vec_with_limit(compressed, limit)
            .map_err(|_| ZipError::InflateFailed)
    }

    /// Scans backwards for a four-byte little-endian signature.
    ///
    /// Backwards and by signature, not at a fixed offset: an archive comment pushes the
    /// EOCD arbitrarily far from the tail, and `archive-comment.cbz` in the corpus exists
    /// to catch a reader that forgets.
    pub(crate) fn last_index(signature: u32, data: &[u8]) -> Option<usize> {
        let pattern = signature.to_le_bytes();
        data.windows(4).rposition(|window| window == pattern)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemorySource;

    #[test]
    fn a_source_with_no_eocd_signature_is_reported_as_such() {
        let source: Arc<dyn RandomAccessSource> = Arc::new(MemorySource::new(vec![0x41; 1024]));
        assert_eq!(
            ZipReader::open(source).err(),
            Some(ZipError::NoCentralDirectory)
        );
    }

    #[test]
    fn inflate_of_nothing_is_nothing_and_a_cap_holds() {
        assert!(ZipReader::inflate(&[], 0).unwrap().is_empty());
        // Junk never inflates to anything, however large the header claims.
        assert_eq!(
            ZipReader::inflate(&[0x00], u64::MAX).err(),
            Some(ZipError::InflateFailed)
        );
    }

    #[test]
    fn the_last_signature_wins() {
        let bytes = [0x50, 0x4B, 0x05, 0x06, 0xFF, 0x50, 0x4B, 0x05, 0x06, 0x00];
        assert_eq!(ZipReader::last_index(EOCD_SIGNATURE, &bytes), Some(5));
        assert_eq!(ZipReader::last_index(EOCD_SIGNATURE, &[0x50, 0x4B]), None);
    }
}
