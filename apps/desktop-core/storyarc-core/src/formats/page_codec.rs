//! What a page's bytes say they are encoded with. Mirrored from `PageCodec.swift`.
//!
//! `publication-formats`: "a page in an unsupported codec displays a placeholder naming the
//! codec, and does not break pagination". Naming it is the whole job of this type. One page
//! saying "JPEG" among a hundred that decoded is a damaged entry; every page saying "JPEG
//! XL" is a format this device has no decoder for.
//!
//! Read from the bytes rather than the extension, for the reason the sniffer reads
//! containers that way: a page named `.jpg` that is really AVIF is common in files converted
//! in bulk, and a name is not evidence.

use super::page_ordering::PageOrdering;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageCodec {
    Jpeg,
    Png,
    Gif,
    Webp,
    Avif,
    Heic,
    JpegXl,
    Bmp,
    Tiff,
}

impl PageCodec {
    /// How the codec is named to the reader: format names rather than prose, so the
    /// localised sentence wraps them.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Jpeg => "JPEG",
            Self::Png => "PNG",
            Self::Gif => "GIF",
            Self::Webp => "WebP",
            Self::Avif => "AVIF",
            Self::Heic => "HEIC",
            Self::JpegXl => "JPEG XL",
            Self::Bmp => "BMP",
            Self::Tiff => "TIFF",
        }
    }

    /// Longest prefix any signature below needs. An ISO base-media brand sits at offset 8,
    /// so twelve bytes covers every case.
    pub const PROBE_LENGTH: usize = 12;

    /// The codec a byte prefix identifies, or `None` when nothing matches.
    ///
    /// Ordered so that the unambiguous fixed signatures answer first and the two
    /// container-shaped families — RIFF and ISO base media — are reached only when nothing
    /// shorter matched.
    pub fn of(prefix: &[u8]) -> Option<Self> {
        let bytes = &prefix[..prefix.len().min(Self::PROBE_LENGTH)];
        Self::fixed_signature(bytes).or_else(|| Self::container(bytes))
    }

    fn fixed_signature(bytes: &[u8]) -> Option<Self> {
        if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
            return Some(Self::Jpeg);
        }
        if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return Some(Self::Png);
        }
        if bytes.starts_with(b"GIF8") {
            return Some(Self::Gif);
        }
        if bytes.starts_with(b"BM") {
            return Some(Self::Bmp);
        }
        if bytes.starts_with(&[0x49, 0x49, 0x2A, 0x00])
            || bytes.starts_with(&[0x4D, 0x4D, 0x00, 0x2A])
        {
            return Some(Self::Tiff);
        }
        // A naked JPEG XL codestream, and the ISO-BMFF container form.
        if bytes.starts_with(&[0xFF, 0x0A])
            || bytes.starts_with(&[
                0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A,
            ])
        {
            return Some(Self::JpegXl);
        }
        None
    }

    /// The two codecs that live inside a general-purpose container, where the tag that says
    /// which is not at the start of the file.
    fn container(bytes: &[u8]) -> Option<Self> {
        // RIFF....WEBP: the four bytes between are the chunk length, not a signature.
        if Self::ascii(bytes, 0) == Some("RIFF") && Self::ascii(bytes, 8) == Some("WEBP") {
            return Some(Self::Webp);
        }
        // ISO base media: `ftyp` at offset 4, then the brand. AVIF and HEIC are the same
        // container with different brands, which is why one check answers both.
        if Self::ascii(bytes, 4) != Some("ftyp") {
            return None;
        }
        match Self::ascii(bytes, 8)? {
            "avif" | "avis" => Some(Self::Avif),
            // `mif1` and `msf1` are the generic HEIF brands; the rest are HEVC-coded
            // images. All of them arrive from a phone camera and all are called HEIC.
            "heic" | "heix" | "hevc" | "hevx" | "heim" | "heis" | "mif1" | "msf1" => {
                Some(Self::Heic)
            }
            _ => None,
        }
    }

    /// Four bytes at an offset, as ASCII, or `None` when the prefix is too short.
    fn ascii(bytes: &[u8], offset: usize) -> Option<&str> {
        let slice = bytes.get(offset..offset + 4)?;
        std::str::from_utf8(slice).ok().filter(|s| s.is_ascii())
    }

    /// What to call a page that could not be decoded, given whatever is known about it.
    ///
    /// The bytes first, the extension second, and `None` when neither says anything —
    /// because "this page could not be read" is a better sentence than a codec name
    /// invented from a file name nobody chose.
    pub fn name(data: Option<&[u8]>, path: &str) -> Option<&'static str> {
        if let Some(codec) = data.and_then(Self::of) {
            return Some(codec.display_name());
        }
        Self::by_extension(&PageOrdering::extension(path)?).map(Self::display_name)
    }

    /// The extensions `PageOrdering` will attempt, mapped to what they claim to be.
    fn by_extension(ext: &str) -> Option<Self> {
        match ext {
            "jpg" | "jpeg" => Some(Self::Jpeg),
            "png" => Some(Self::Png),
            "gif" => Some(Self::Gif),
            "webp" => Some(Self::Webp),
            "avif" => Some(Self::Avif),
            "heic" | "heif" => Some(Self::Heic),
            "jxl" => Some(Self::JpegXl),
            "bmp" => Some(Self::Bmp),
            "tif" | "tiff" => Some(Self::Tiff),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signatures_are_read_from_the_bytes() {
        assert_eq!(
            PageCodec::of(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some(PageCodec::Jpeg)
        );
        assert_eq!(
            PageCodec::of(b"RIFF\x10\0\0\0WEBPVP8 "),
            Some(PageCodec::Webp)
        );
        assert_eq!(PageCodec::of(b"\0\0\0\x18ftypavif"), Some(PageCodec::Avif));
        assert_eq!(PageCodec::of(b"\0\0\0\x18ftypheic"), Some(PageCodec::Heic));
        assert_eq!(PageCodec::of(&[0xFF, 0x0A, 0x00]), Some(PageCodec::JpegXl));
        assert_eq!(PageCodec::of(b"not an image"), None);
    }

    #[test]
    fn a_name_comes_from_the_bytes_first_and_the_extension_second() {
        assert_eq!(
            PageCodec::name(Some(&[0xFF, 0xD8, 0xFF]), "page.png"),
            Some("JPEG")
        );
        assert_eq!(PageCodec::name(None, "page.jxl"), Some("JPEG XL"));
        assert_eq!(PageCodec::name(None, "page"), None);
        assert_eq!(PageCodec::name(Some(b"junk"), "page.txt"), None);
    }
}
