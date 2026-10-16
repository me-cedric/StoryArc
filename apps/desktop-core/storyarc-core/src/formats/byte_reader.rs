//! Little-endian reads over a byte buffer, bounds-checked.
//!
//! Every ZIP structure is little-endian. Bounds checks are not optional here: this parser
//! runs on untrusted input, and `SECURITY.md` names archive parsing as the largest attack
//! surface in the app. No length read out of a file is ever used to allocate without being
//! checked against the buffer first.

use super::zip::ZipError;

pub(crate) struct ByteReader<'a> {
    bytes: &'a [u8],
    cursor: usize,
}

impl<'a> ByteReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, cursor: 0 }
    }

    pub fn at(bytes: &'a [u8], offset: usize) -> Self {
        Self {
            bytes,
            cursor: offset.min(bytes.len()),
        }
    }

    pub fn remaining(&self) -> usize {
        self.bytes.len() - self.cursor
    }

    pub fn skip(&mut self, count: usize) -> Result<(), ZipError> {
        if count > self.remaining() {
            return Err(ZipError::Malformed("skip past end"));
        }
        self.cursor += count;
        Ok(())
    }

    pub fn u16(&mut self) -> Result<u16, ZipError> {
        let bytes = self.read(2)?;
        Ok(u16::from_le_bytes([bytes[0], bytes[1]]))
    }

    pub fn u32(&mut self) -> Result<u32, ZipError> {
        let bytes = self.read(4)?;
        Ok(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    pub fn u64(&mut self) -> Result<u64, ZipError> {
        let bytes = self.read(8)?;
        let mut fixed = [0; 8];
        fixed.copy_from_slice(bytes);
        Ok(u64::from_le_bytes(fixed))
    }

    pub fn read(&mut self, count: usize) -> Result<&'a [u8], ZipError> {
        if count > self.remaining() {
            return Err(ZipError::Malformed("read past end"));
        }
        let slice = &self.bytes[self.cursor..self.cursor + count];
        self.cursor += count;
        Ok(slice)
    }

    /// An entry name. ZIP stores UTF-8 when general-purpose bit 11 is set, and an
    /// unspecified code page otherwise. Falling back to ISO-8859-1 keeps every byte
    /// round-trippable rather than losing a name to a decode failure.
    pub fn string(&mut self, count: usize, is_utf8: bool) -> Result<String, ZipError> {
        let raw = self.read(count)?;
        Ok(decode_name(raw, is_utf8))
    }
}

/// UTF-8 when declared and valid, ISO-8859-1 otherwise — the latter maps every byte to a
/// character, so no name is lost.
pub(crate) fn decode_name(raw: &[u8], is_utf8: bool) -> String {
    if is_utf8 && let Ok(text) = std::str::from_utf8(raw) {
        return text.to_owned();
    }
    latin1(raw)
}

/// ISO-8859-1: each byte is the code point of the same value.
pub(crate) fn latin1(raw: &[u8]) -> String {
    raw.iter().map(|&byte| byte as char).collect()
}
