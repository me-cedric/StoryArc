//! Where a ZIP says its entries are, split out of [`ZipReader`] as `ZipCentralDirectory.swift`
//! is on iOS.
//!
//! Finding and parsing the central directory is the half of the format that deals in
//! offsets, ZIP64 extensions and the end-of-central-directory record. Reading an entry is
//! the other half. They share a type and nothing else.

use super::byte_reader::ByteReader;
use super::zip::{
    CENTRAL_ENTRY_SIGNATURE, ZIP64_EOCD_SIGNATURE, ZIP64_LOCATOR_SIGNATURE, ZipEntry, ZipError,
    ZipReader,
};
use crate::io::{HeaderBounds, RandomAccessSource};

pub(crate) struct Zip64Directory {
    pub entry_count: u64,
    pub size: u64,
    pub offset: u64,
}

#[derive(Default)]
struct Zip64Fields {
    uncompressed_size: Option<u64>,
    compressed_size: Option<u64>,
    local_offset: Option<u64>,
}

impl ZipReader {
    /// Reads the entries out of a central directory.
    ///
    /// `source_length` is not decoration. A zip64 extra field can override an entry's
    /// offset and compressed size with any 64-bit number, and those numbers are added to
    /// things later — so they are range-checked here, where they are parsed, rather than in
    /// the guard that would wrap on them.
    pub(crate) fn parse_central_directory(
        data: &[u8],
        _expected_count: u64,
        source_length: u64,
    ) -> Result<Vec<ZipEntry>, ZipError> {
        let mut reader = ByteReader::new(data);
        let mut parsed = Vec::new();

        while reader.remaining() >= 46 {
            if reader.u32()? != CENTRAL_ENTRY_SIGNATURE {
                // Ran off the end of the entries. Not an error: the directory may be
                // followed by other records.
                break;
            }
            reader.skip(2 + 2)?; // versions
            let flags = reader.u16()?;
            let method = reader.u16()?;
            reader.skip(2 + 2 + 4)?; // mod time/date, crc
            let compressed32 = reader.u32()?;
            let uncompressed32 = reader.u32()?;
            let name_length = usize::from(reader.u16()?);
            let extra_length = usize::from(reader.u16()?);
            let comment_length = usize::from(reader.u16()?);
            reader.skip(2 + 2 + 4)?; // disk start, attributes
            let local_offset32 = reader.u32()?;

            let is_utf8 = flags & 0x0800 != 0;
            let path = reader.string(name_length, is_utf8)?;
            let extra = reader.read(extra_length)?;
            reader.skip(comment_length)?;

            let mut compressed_size = u64::from(compressed32);
            let mut uncompressed_size = u64::from(uncompressed32);
            let mut local_offset = u64::from(local_offset32);

            // Zip64 extended information overrides whichever fields were maxed.
            if let Some(zip64) = Self::parse_zip64_extra(
                extra,
                uncompressed32 == 0xFFFF_FFFF,
                compressed32 == 0xFFFF_FFFF,
                local_offset32 == 0xFFFF_FFFF,
            )? {
                if let Some(value) = zip64.uncompressed_size {
                    uncompressed_size = value;
                }
                if let Some(value) = zip64.compressed_size {
                    compressed_size = value;
                }
                if let Some(value) = zip64.local_offset {
                    local_offset = value;
                }
            }
            let entry = ZipEntry {
                path,
                compressed_size,
                uncompressed_size,
                local_header_offset: local_offset,
                compression_method: method,
                is_encrypted: flags & 0x0001 != 0,
            };
            Self::check_fits(&entry, source_length)?;
            parsed.push(entry);
        }

        // A count mismatch means a damaged directory. Returning what parsed is more useful
        // than refusing the archive, and the caller can compare.
        Ok(parsed)
    }

    /// Refuses an entry whose zip64 override put it outside the file.
    ///
    /// The override is the only way any of these leaves the range a 32-bit field could
    /// hold, and it is unchecked on the wire. An entry that starts or ends outside the file
    /// is a lie about the archive rather than damage to it, so the archive is refused rather
    /// than half-read. `uncompressed_size` is exempt on purpose: compression is what makes a
    /// value larger than the file honest there.
    fn check_fits(entry: &ZipEntry, source_length: u64) -> Result<(), ZipError> {
        if HeaderBounds::position(entry.local_header_offset, source_length)
            && HeaderBounds::position(entry.compressed_size, source_length)
        {
            Ok(())
        } else {
            Err(ZipError::Malformed(
                "central directory entry outside the source",
            ))
        }
    }

    /// Walks the extra-field blocks looking for header id 0x0001. Its payload carries only
    /// the fields that were sentinel-valued, in a fixed order.
    fn parse_zip64_extra(
        extra: &[u8],
        needs_uncompressed: bool,
        needs_compressed: bool,
        needs_offset: bool,
    ) -> Result<Option<Zip64Fields>, ZipError> {
        if !(needs_uncompressed || needs_compressed || needs_offset) {
            return Ok(None);
        }
        let mut reader = ByteReader::new(extra);
        while reader.remaining() >= 4 {
            let header_id = reader.u16()?;
            let size = usize::from(reader.u16()?);
            if reader.remaining() < size {
                break;
            }
            if header_id != 0x0001 {
                reader.skip(size)?;
                continue;
            }
            let mut fields = Zip64Fields::default();
            let mut consumed = 0;
            if needs_uncompressed && size - consumed >= 8 {
                fields.uncompressed_size = Some(reader.u64()?);
                consumed += 8;
            }
            if needs_compressed && size - consumed >= 8 {
                fields.compressed_size = Some(reader.u64()?);
                consumed += 8;
            }
            if needs_offset && size - consumed >= 8 {
                fields.local_offset = Some(reader.u64()?);
            }
            return Ok(Some(fields));
        }
        Ok(None)
    }

    pub(crate) fn read_zip64(
        tail: &[u8],
        tail_offset: u64,
        source: &dyn RandomAccessSource,
    ) -> Result<Option<Zip64Directory>, ZipError> {
        let Some(locator_index) = Self::last_index(ZIP64_LOCATOR_SIGNATURE, tail) else {
            return Ok(None);
        };
        let mut locator = ByteReader::at(tail, locator_index);
        locator.u32()?; // signature
        locator.skip(4)?; // disk holding the zip64 EOCD
        let record_offset = locator.u64()?;

        // `record_offset + 56` on a number the file chose: checked rather than performed.
        if !HeaderBounds::span(record_offset, 56, source.length()) {
            return Err(ZipError::Malformed("zip64 EOCD offset outside the source"));
        }

        let record: Vec<u8> = if record_offset >= tail_offset {
            let start = (record_offset - tail_offset) as usize;
            tail[start..(start + 56).min(tail.len())].to_vec()
        } else {
            source.read_exactly(record_offset, 56)?
        };

        let mut reader = ByteReader::new(&record);
        if reader.u32()? != ZIP64_EOCD_SIGNATURE {
            return Err(ZipError::Malformed("zip64 EOCD signature missing"));
        }
        reader.skip(8 + 2 + 2 + 4 + 4)?; // record size, versions, disk numbers
        reader.skip(8)?; // entries on this disk
        let entry_count = reader.u64()?;
        let size = reader.u64()?;
        let offset = reader.u64()?;
        // Checked here rather than by the caller: two values whose sum leaves u64 pass
        // every `<= length` test on their own and wrap on the addition that follows.
        if !HeaderBounds::span(offset, size, source.length()) {
            return Err(ZipError::Malformed(
                "zip64 central directory outside the source",
            ));
        }
        Ok(Some(Zip64Directory {
            entry_count,
            size,
            offset,
        }))
    }
}
