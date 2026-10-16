//! Reads RAR *headers*, and the bytes of stored entries. Mirrored from StoryArcKit's
//! `RarReader.swift` and `RarEntry.swift`.
//!
//! Deliberately not a RAR decoder. Everything the library needs in order to index a
//! publication — page names, page sizes, the cover, whether the archive is solid or
//! encrypted — lives in the headers, and headers are a documented layout with no compression
//! in them. So this is written here, the same reasoning ADR-0008 applies to ZIP, and
//! libarchive's remaining job shrinks to one function: turn a compressed entry's packed
//! bytes into unpacked bytes (`RarDecoder`).
//!
//! This parser runs on untrusted input. `SECURITY.md` names archive parsing as the largest
//! attack surface in the app: every offset is bounds-checked against the source before use,
//! no length from a header is used to allocate, and the entry count is capped.

use std::sync::Arc;

use super::byte_reader::latin1;
use super::rar_decoder::RarDecoder;
use crate::io::{HeaderBounds, RandomAccessSource, SourceError};

/// One file inside a RAR archive.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RarEntry {
    pub path: String,
    /// Size after decompression. What the page decoder will see.
    pub size: u64,
    /// Size on disk. Equal to `size` when the entry is stored.
    pub packed_size: u64,
    /// Where the entry's packed bytes start.
    pub data_offset: u64,
    /// Stored entries carry their bytes verbatim, so they need no decoder at all.
    pub is_stored: bool,
    /// Solid entries cannot be decompressed without the entries before them.
    pub is_solid: bool,
    pub is_encrypted: bool,
    /// Where the entry's own header block starts. With `data_offset` and `packed_size` it
    /// bounds everything a decoder needs for a non-solid entry.
    pub header_offset: u64,
}

/// Which RAR format an archive uses. They share an extension and nothing else: different
/// signatures, different header layouts, different integer encodings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RarGeneration {
    Rar4,
    Rar5,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RarError {
    Malformed(&'static str),
    NotRar,
    /// The entry is compressed or encrypted, and reading it needs the decoder. Distinct
    /// from `Malformed`: the archive is fine.
    NeedsDecoder,
    /// More headers than any real publication has. A guard against a crafted file that
    /// would otherwise be read into an unbounded list.
    TooManyEntries,
    Source(SourceError),
}

impl From<SourceError> for RarError {
    fn from(error: SourceError) -> Self {
        Self::Source(error)
    }
}

impl std::fmt::Display for RarError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Malformed(reason) => write!(f, "malformed RAR: {reason}"),
            Self::NotRar => f.write_str("not a RAR"),
            Self::NeedsDecoder => f.write_str("entry needs the decoder"),
            Self::TooManyEntries => f.write_str("too many entries"),
            Self::Source(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for RarError {}

pub const RAR4_SIGNATURE: [u8; 7] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];
pub const RAR5_SIGNATURE: [u8; 8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00];

/// A comic has hundreds of pages. Tens of thousands means a crafted file.
const ENTRY_LIMIT: usize = 50_000;
/// Headers are small. Anything claiming more is not a header.
const MAX_HEADER_SIZE: u64 = 1 << 20;

/// What a header walk found: the entries, the two flags that decide whether the archive can
/// be read at all, and where the main header ends.
struct Scan {
    entries: Vec<RarEntry>,
    is_solid: bool,
    is_encrypted: bool,
    main_header_end: u64,
}

pub struct RarReader {
    generation: RarGeneration,
    entries: Vec<RarEntry>,
    /// The archive-level solid flag. Individual entries carry their own.
    is_solid_archive: bool,
    /// Set when headers or entries are encrypted. `publication-formats` requires saying so
    /// rather than prompting for a password.
    is_encrypted: bool,
    /// Where the blocks before the first entry end: the signature and the main header.
    main_header_end: u64,
    source: Arc<dyn RandomAccessSource>,
}

impl RarReader {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, RarError> {
        let head = source.read(0, RAR5_SIGNATURE.len())?;
        let (generation, scan) = if head.starts_with(&RAR5_SIGNATURE) {
            (RarGeneration::Rar5, Self::parse_rar5(source.as_ref())?)
        } else if head.starts_with(&RAR4_SIGNATURE) {
            (RarGeneration::Rar4, Self::parse_rar4(source.as_ref())?)
        } else {
            return Err(RarError::NotRar);
        };
        Ok(Self {
            generation,
            entries: scan.entries,
            is_solid_archive: scan.is_solid,
            is_encrypted: scan.is_encrypted,
            main_header_end: scan.main_header_end,
            source,
        })
    }

    pub fn generation(&self) -> RarGeneration {
        self.generation
    }

    pub fn entries(&self) -> &[RarEntry] {
        &self.entries
    }

    pub fn is_encrypted(&self) -> bool {
        self.is_encrypted
    }

    /// True when any entry cannot be reached without decompressing the ones before it —
    /// the question `Streaming capability per format` asks. A solid archive is never
    /// streamable, on either generation.
    pub fn is_solid(&self) -> bool {
        self.is_solid_archive || self.entries.iter().any(|entry| entry.is_solid)
    }

    /// Whether the archive can be read at all once it is local.
    ///
    /// This is where the two generations part company, measured rather than assumed.
    /// libarchive reads a solid RAR5 completely — its own test suite's
    /// `test_read_format_rar5_solid.rar` yields all seven entries. It cannot read a solid
    /// RAR4 at all: `read_header()` returns `ARCHIVE_FATAL` on any file header carrying
    /// `FHD_SOLID`, with no compression-method check and no fallback. So a solid RAR4 is
    /// unsupported and downloading it changes nothing, while a solid RAR5 is merely
    /// download-only.
    pub fn is_readable_when_local(&self) -> bool {
        !(self.is_solid() && self.generation == RarGeneration::Rar4)
    }

    /// A stored entry's bytes. Compressed entries need the decoder, which is the seam
    /// libarchive fills.
    pub fn data(&self, entry: &RarEntry) -> Result<Vec<u8>, RarError> {
        if entry.is_encrypted || !entry.is_stored {
            return Err(RarError::NeedsDecoder);
        }
        if !HeaderBounds::span(entry.data_offset, entry.packed_size, self.source.length()) {
            return Err(RarError::Malformed("entry lies outside the source"));
        }
        Ok(self
            .source
            .read_exactly(entry.data_offset, entry.packed_size as usize)?)
    }

    /// One non-solid entry as an archive of its own: the signature and main header, then the
    /// entry's header and packed bytes. Nothing between them and nothing after is read.
    ///
    /// A non-solid entry decodes without the entries before it, so these bytes are all
    /// libarchive needs. Two ranged reads replace the whole file, which is what lets a
    /// compressed CBR stream from a share (`publication-formats`, *Streaming capability per
    /// format*). Every length here comes from a header, so each is bounded first.
    pub fn isolated(&self, entry: &RarEntry) -> Result<Vec<u8>, RarError> {
        let length = self.source.length();
        let header_length = entry
            .data_offset
            .checked_sub(entry.header_offset)
            .filter(|&n| n > 0 && n <= MAX_HEADER_SIZE);
        let fits = self.main_header_end > 0
            && self.main_header_end <= MAX_HEADER_SIZE
            && self.main_header_end <= entry.header_offset
            && entry.packed_size <= RarDecoder::MAX_ENTRY_BYTES as u64
            && HeaderBounds::span(entry.data_offset, entry.packed_size, length);
        let (Some(header_length), true) = (header_length, fits) else {
            return Err(RarError::Malformed("entry lies outside the source"));
        };
        let mut out = self.source.read_exactly(0, self.main_header_end as usize)?;
        out.extend(self.source.read_exactly(
            entry.header_offset,
            (header_length + entry.packed_size) as usize,
        )?);
        Ok(out)
    }

    // ── RAR4 ──────────────────────────────────────────────────────────────

    fn parse_rar4(source: &dyn RandomAccessSource) -> Result<Scan, RarError> {
        let length = source.length();
        let mut entries = Vec::new();
        let mut solid_archive = false;
        let mut encrypted = false;
        let mut main_header_end = 0;
        let mut offset = RAR4_SIGNATURE.len() as u64;

        while offset + 7 <= length {
            let head = source.read_exactly(offset, 7)?;
            let flags = u32::from(head[3]) | u32::from(head[4]) << 8;
            let header_size = u64::from(head[5]) | u64::from(head[6]) << 8;
            if !(7..=MAX_HEADER_SIZE).contains(&header_size)
                || !HeaderBounds::span(offset, header_size, length)
            {
                break;
            }

            let block_type = head[2];
            if block_type == 0x73 {
                // Main archive header. 0x0080 means the block headers themselves are
                // encrypted, so nothing past this point can be parsed at all.
                solid_archive = flags & 0x0008 != 0;
                if flags & 0x0080 != 0 {
                    return Ok(Scan {
                        entries: Vec::new(),
                        is_solid: solid_archive,
                        is_encrypted: true,
                        main_header_end: 0,
                    });
                }
                offset += header_size;
                main_header_end = offset;
                continue;
            }
            if block_type == 0x7B {
                break; // end of archive
            }

            if block_type != 0x74 {
                // Not a file header: skip it whole, payload included.
                let add_size = if flags & 0x8000 != 0 {
                    Self::rar4_add_size(source, offset, header_size)?
                } else {
                    0
                };
                let Some(next) = offset
                    .checked_add(header_size)
                    .and_then(|n| n.checked_add(add_size))
                else {
                    break;
                };
                offset = next;
                continue;
            }

            let header = source.read_exactly(offset, header_size as usize)?;
            if header.len() < 32 {
                break;
            }

            let mut packed = u64::from(le32(&header, 7));
            let mut unpacked = u64::from(le32(&header, 11));
            let method = header[25];
            let name_size = usize::from(header[26]) | usize::from(header[27]) << 8;
            let mut cursor = 32;
            if flags & 0x0100 != 0 {
                // LHD_LARGE: 64-bit sizes in two halves.
                if header.len() < cursor + 8 {
                    break;
                }
                packed |= u64::from(le32(&header, cursor)) << 32;
                unpacked |= u64::from(le32(&header, cursor + 4)) << 32;
                cursor += 8;
            }
            if cursor + name_size > header.len() {
                break;
            }
            let raw_name = &header[cursor..cursor + name_size];
            let is_directory = flags & 0x00E0 == 0x00E0;
            let entry_encrypted = flags & 0x0004 != 0;
            if entry_encrypted {
                encrypted = true;
            }

            let data_offset = offset + header_size;
            if !is_directory && HeaderBounds::span(data_offset, packed, length) {
                if entries.len() >= ENTRY_LIMIT {
                    return Err(RarError::TooManyEntries);
                }
                entries.push(RarEntry {
                    path: Self::rar4_name(raw_name, flags & 0x0200 != 0),
                    size: unpacked,
                    packed_size: packed,
                    data_offset,
                    is_stored: method == 0x30,
                    is_solid: flags & 0x0010 != 0,
                    is_encrypted: entry_encrypted,
                    header_offset: offset,
                });
            }
            let Some(next) = data_offset.checked_add(packed) else {
                break;
            };
            offset = next;
        }

        Ok(Scan {
            entries,
            is_solid: solid_archive,
            is_encrypted: encrypted,
            main_header_end,
        })
    }

    /// A non-file block's payload size, which sits directly after its 7-byte head.
    fn rar4_add_size(
        source: &dyn RandomAccessSource,
        offset: u64,
        header_size: u64,
    ) -> Result<u64, RarError> {
        if header_size < 11 {
            return Ok(0);
        }
        let bytes = source.read_exactly(offset, 11)?;
        Ok(u64::from(le32(&bytes, 7)))
    }

    /// RAR4 stores a long name as `asciiName\0<packed unicode>`. The ASCII half is always
    /// present and always valid, so it is what we use.
    ///
    /// ponytail: the packed-unicode half needs RAR's own name codec. Page paths are ASCII in
    /// every comic that exists; revisit if a real file proves otherwise.
    ///
    /// A RAR4 written on Windows separates directories with a backslash, and libarchive's
    /// reader turns every one into a slash. The name here must spell the entry exactly as
    /// libarchive will, because a compressed page is later asked of libarchive *by this
    /// name* — the vendored `rar4-compressed.cbr` carries `testdir\test.txt` and pins it.
    fn rar4_name(raw: &[u8], is_unicode: bool) -> String {
        let ascii = if is_unicode {
            let end = raw.iter().position(|&b| b == 0).unwrap_or(raw.len());
            &raw[..end]
        } else {
            raw
        };
        std::str::from_utf8(ascii)
            .map_or_else(|_| latin1(ascii), str::to_owned)
            .replace('\\', "/")
    }

    // ── RAR5 ──────────────────────────────────────────────────────────────

    fn parse_rar5(source: &dyn RandomAccessSource) -> Result<Scan, RarError> {
        let length = source.length();
        let mut entries = Vec::new();
        let mut solid_archive = false;
        let mut encrypted = false;
        let mut main_header_end = 0;
        let mut offset = RAR5_SIGNATURE.len() as u64;

        while offset + 8 <= length {
            // The header's own size is a vint, so read a window big enough to hold the size
            // field and then the header it describes.
            let window = source.read(offset, 64)?;
            if window.len() <= 4 {
                break;
            }
            let mut cursor = 4; // past the header CRC32
            let Some(header_size) =
                vint(&window, &mut cursor).filter(|&n| n > 0 && n <= MAX_HEADER_SIZE)
            else {
                break;
            };

            let header_start = offset + cursor as u64;
            if !HeaderBounds::span(header_start, header_size, length) {
                break;
            }
            let bytes = source.read_exactly(header_start, header_size as usize)?;
            let mut read = 0;

            let (Some(block_type), Some(flags)) =
                (vint(&bytes, &mut read), vint(&bytes, &mut read))
            else {
                break;
            };
            let mut extra_size = 0;
            let mut data_size = 0;
            if flags & 0x0001 != 0 {
                extra_size = vint(&bytes, &mut read).unwrap_or(0);
            }
            if flags & 0x0002 != 0 {
                data_size = vint(&bytes, &mut read).unwrap_or(0);
            }

            let data_offset = header_start + header_size;
            let Some(next_offset) = data_offset.checked_add(data_size) else {
                break;
            };

            match block_type {
                1 => {
                    // Main archive header.
                    if let Some(archive_flags) = vint(&bytes, &mut read) {
                        solid_archive = archive_flags & 0x0004 != 0;
                    }
                    main_header_end = next_offset;
                }
                4 => {
                    // Encrypted headers: nothing past this point can be parsed.
                    return Ok(Scan {
                        entries: Vec::new(),
                        is_solid: solid_archive,
                        is_encrypted: true,
                        main_header_end: 0,
                    });
                }
                5 => {
                    // End of archive.
                    return Ok(Scan {
                        entries,
                        is_solid: solid_archive,
                        is_encrypted: encrypted,
                        main_header_end,
                    });
                }
                2 | 3 => {
                    // File, and service headers such as the archive comment.
                    let (Some(file_flags), Some(unpacked), Some(_attributes)) = (
                        vint(&bytes, &mut read),
                        vint(&bytes, &mut read),
                        vint(&bytes, &mut read),
                    ) else {
                        break;
                    };
                    if file_flags & 0x0002 != 0 {
                        read += 4; // mtime
                    }
                    if file_flags & 0x0004 != 0 {
                        read += 4; // data CRC32
                    }
                    let (Some(compression), Some(_host_os), Some(name_size)) = (
                        vint(&bytes, &mut read),
                        vint(&bytes, &mut read),
                        vint(&bytes, &mut read),
                    ) else {
                        break;
                    };
                    let Some(name_end) = usize::try_from(name_size)
                        .ok()
                        .and_then(|n| read.checked_add(n))
                        .filter(|&end| end <= bytes.len())
                    else {
                        break;
                    };
                    let name = String::from_utf8_lossy(&bytes[read..name_end]).into_owned();

                    let entry_encrypted = extra_size > 0
                        && header_size >= extra_size
                        && Self::has_encryption_record(&bytes, (header_size - extra_size) as usize);
                    if entry_encrypted {
                        encrypted = true;
                    }

                    // Only real files. A service header carries metadata, and file flag
                    // bit 0 marks a directory.
                    if block_type == 2
                        && file_flags & 0x0001 == 0
                        && HeaderBounds::span(data_offset, data_size, length)
                    {
                        if entries.len() >= ENTRY_LIMIT {
                            return Err(RarError::TooManyEntries);
                        }
                        entries.push(RarEntry {
                            path: name,
                            size: unpacked,
                            packed_size: data_size,
                            data_offset,
                            // CompressionInfo bits 7-9 hold the method; 0 is store.
                            is_stored: (compression >> 7) & 0x07 == 0,
                            is_solid: compression & 0x40 != 0,
                            is_encrypted: entry_encrypted,
                            header_offset: offset,
                        });
                    }
                }
                _ => {}
            }

            if next_offset <= offset {
                break; // never move backwards
            }
            offset = next_offset;
        }
        Ok(Scan {
            entries,
            is_solid: solid_archive,
            is_encrypted: encrypted,
            main_header_end,
        })
    }

    /// Whether a file header's extra area declares encryption (record type 1). Records are
    /// `size(vint) type(vint) payload`, with `size` covering the type and payload.
    fn has_encryption_record(bytes: &[u8], start: usize) -> bool {
        let mut cursor = start;
        while cursor < bytes.len() {
            let mut probe = cursor;
            let Some(size) = vint(bytes, &mut probe).filter(|&n| n > 0) else {
                return false;
            };
            let mut type_cursor = probe;
            let Some(record_type) = vint(bytes, &mut type_cursor) else {
                return false;
            };
            if record_type == 1 {
                return true;
            }
            let Some(next) = usize::try_from(size)
                .ok()
                .and_then(|n| probe.checked_add(n))
                .filter(|&next| next > cursor && next <= bytes.len())
            else {
                return false;
            };
            cursor = next;
        }
        false
    }
}

fn le32(bytes: &[u8], at: usize) -> u32 {
    match bytes.get(at..at + 4) {
        Some(b) => u32::from_le_bytes([b[0], b[1], b[2], b[3]]),
        None => 0,
    }
}

/// RAR5's variable-length integer: seven bits per byte, low group first, high bit marks
/// continuation. Capped at ten groups so a run of 0x80 bytes cannot spin, and rejected on
/// overflow rather than wrapping.
pub(crate) fn vint(bytes: &[u8], cursor: &mut usize) -> Option<u64> {
    let mut value: u64 = 0;
    let mut shift = 0;
    let mut groups = 0;
    while *cursor < bytes.len() && groups < 10 {
        let byte = bytes[*cursor];
        *cursor += 1;
        groups += 1;
        if shift >= 63 {
            return None;
        }
        value |= u64::from(byte & 0x7F) << shift;
        if byte & 0x80 == 0 {
            // The Swift reader refuses a value that does not fit a signed 64-bit integer,
            // and so does this one, so both answer the same way to the same bytes.
            return (value <= i64::MAX as u64).then_some(value);
        }
        shift += 7;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemorySource;

    fn source(bytes: Vec<u8>) -> Arc<dyn RandomAccessSource> {
        Arc::new(MemorySource::new(bytes))
    }

    #[test]
    fn a_signature_with_nothing_behind_it_yields_no_entries_not_a_crash() {
        let reader = RarReader::open(source(RAR5_SIGNATURE.to_vec())).unwrap();
        assert!(reader.entries().is_empty());
        assert_eq!(reader.generation(), RarGeneration::Rar5);
    }

    #[test]
    fn bytes_that_are_not_a_rar_are_rejected_as_such() {
        assert_eq!(
            RarReader::open(source(vec![0x41; 512])).err(),
            Some(RarError::NotRar)
        );
    }

    #[test]
    fn a_header_claiming_a_size_past_the_end_stops_the_walk() {
        let mut bytes = RAR5_SIGNATURE.to_vec();
        bytes.extend_from_slice(&[0, 0, 0, 0]); // header CRC
        bytes.extend_from_slice(&[0xFF, 0xFF, 0xFF, 0x7F]); // a size far larger than the file
        let reader = RarReader::open(source(bytes)).unwrap();
        assert!(reader.entries().is_empty());
    }

    #[test]
    fn a_run_of_continuation_bytes_cannot_spin_the_vint_reader() {
        let mut cursor = 0;
        assert_eq!(vint(&[0x80; 64], &mut cursor), None);
        assert!(cursor <= 10);
        let mut cursor = 0;
        assert_eq!(vint(&[0x81, 0x01], &mut cursor), Some(129));
        assert_eq!(cursor, 2);
    }
}
