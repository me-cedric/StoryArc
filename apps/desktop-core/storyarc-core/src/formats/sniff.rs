//! What a file's leading bytes say it is, regardless of its name. Mirrored from
//! `PublicationFormat.swift`'s `FormatSniffer`.

use super::tar;

/// The container a byte prefix identifies.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Container {
    Zip,
    Rar,
    SevenZip,
    Pdf,
    Tar,
    Mp4,
    Mp3,
    Flac,
    Ogg,
    /// An MPEG-4 file whose brand declares a store's content protection.
    ///
    /// Its own case, because `publication-formats` requires the refusal to be "distinct
    /// from an unsupported container": the format is supported and this particular file is
    /// locked, and those two need different words.
    ProtectedAudiobook,
}

impl Container {
    /// Whether a player rather than a reader opens this.
    ///
    /// Protected audio answers `true`: it is refused for being locked, not for being the
    /// wrong kind of file, and a caller that routed it to a comic reader would produce the
    /// unsupported-container message the spec forbids for it.
    pub fn is_audio(self) -> bool {
        matches!(
            self,
            Self::Mp4 | Self::Mp3 | Self::Flac | Self::Ogg | Self::ProtectedAudiobook
        )
    }

    /// How the container is named to the user when StoryArc refuses it.
    ///
    /// `publication-formats` forbids a generic parse failure: someone handed a 7-Zip comic
    /// to a comic reader and deserves to be told that, not that the file is broken.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Zip => "ZIP",
            Self::Rar => "RAR",
            Self::SevenZip => "7-Zip",
            Self::Pdf => "PDF",
            Self::Tar => "TAR",
            Self::Mp4 => "MPEG-4 audio",
            Self::Mp3 => "MP3",
            Self::Flac => "FLAC",
            Self::Ogg => "Ogg",
            Self::ProtectedAudiobook => "protected audiobook",
        }
    }
}

pub struct FormatSniffer;

impl FormatSniffer {
    /// Longest signature we need to see.
    ///
    /// TAR sets the floor: its `ustar` magic sits at offset 257, where every other container
    /// announces itself in the first eight bytes. 265 bytes is still one round trip on an
    /// SMB share, which is the cost that matters.
    pub const PROBE_LENGTH: usize = 265;

    /// The guard, at compile time: shrink the probe back to 8 for the other containers
    /// and CBT detection silently stops working; grow it past a page and a remote probe
    /// starts reading the file rather than its head.
    const _PROBE_COVERS_THE_TAR_MAGIC: () = assert!(
        Self::PROBE_LENGTH >= tar::MAGIC_OFFSET + 5 && Self::PROBE_LENGTH <= 512,
        "the sniffing probe must reach the ustar magic and stay within one page"
    );

    const ZIP: &'static [u8] = b"PK";
    const RAR4: &'static [u8] = &[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];
    const RAR5: &'static [u8] = &[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00];
    const SEVEN_ZIP: &'static [u8] = &[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C];
    const PDF: &'static [u8] = b"%PDF";
    const USTAR: &'static [u8] = b"ustar";
    const ID3: &'static [u8] = b"ID3";
    const FLAC: &'static [u8] = b"fLaC";
    const OGG: &'static [u8] = b"OggS";
    const FTYP: &'static [u8] = b"ftyp";
    /// Where an MPEG-4 file states its brand: the four bytes after `ftyp`.
    const BRAND_OFFSET: usize = 8;

    /// The container a byte prefix identifies, or `None` when nothing matches.
    ///
    /// EPUB and CBZ are both ZIP; distinguishing them needs the archive's contents, which is
    /// why this returns `Zip` and the caller resolves it.
    pub fn container(bytes: &[u8]) -> Option<Container> {
        if bytes.starts_with(Self::RAR5) || bytes.starts_with(Self::RAR4) {
            return Some(Container::Rar);
        }
        if bytes.starts_with(Self::SEVEN_ZIP) {
            return Some(Container::SevenZip);
        }
        if bytes.starts_with(Self::PDF) {
            return Some(Container::Pdf);
        }
        if bytes.starts_with(Self::ZIP) {
            return Some(Container::Zip);
        }
        if bytes.starts_with(Self::FLAC) {
            return Some(Container::Flac);
        }
        if bytes.starts_with(Self::OGG) {
            return Some(Container::Ogg);
        }
        // MPEG-4 announces itself at offset 4, and its *brand* at offset 8 is what
        // separates an audiobook from a locked one. Audible's two brands are checked as
        // brands rather than extensions: a `.m4b` renamed from an `.aax` is still locked.
        if bytes.len() >= Self::BRAND_OFFSET + 4 && &bytes[4..Self::BRAND_OFFSET] == Self::FTYP {
            let brand = &bytes[Self::BRAND_OFFSET..Self::BRAND_OFFSET + 4];
            return Some(if brand == b"aax " || brand == b"aaxc" {
                Container::ProtectedAudiobook
            } else {
                Container::Mp4
            });
        }
        if bytes.starts_with(Self::ID3) {
            return Some(Container::Mp3);
        }
        // A bare MPEG frame: eleven sync bits, and a layer field that is not the reserved
        // `00`. Without the layer check every byte pair from 0xFFE0 up matches, and a
        // truncated ZIP happens to contain plenty of those.
        if bytes.len() >= 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0 && bytes[1] & 0x06 != 0 {
            return Some(Container::Mp3);
        }
        // TAR announces itself at offset 257 rather than at the start, so it is checked last
        // and only when the probe reached that far.
        let magic_end = tar::MAGIC_OFFSET + Self::USTAR.len();
        if bytes.len() >= magic_end && &bytes[tar::MAGIC_OFFSET..magic_end] == Self::USTAR {
            return Some(Container::Tar);
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn containers_are_identified_from_their_magic_bytes() {
        assert_eq!(
            FormatSniffer::container(&[0x50, 0x4B, 0x03, 0x04]),
            Some(Container::Zip)
        );
        assert_eq!(
            FormatSniffer::container(FormatSniffer::RAR4),
            Some(Container::Rar)
        );
        assert_eq!(
            FormatSniffer::container(FormatSniffer::RAR5),
            Some(Container::Rar)
        );
        assert_eq!(
            FormatSniffer::container(FormatSniffer::SEVEN_ZIP),
            Some(Container::SevenZip)
        );
        assert_eq!(FormatSniffer::container(b"%PDF-1.7"), Some(Container::Pdf));
        assert_eq!(FormatSniffer::container(&[0, 1, 2, 3]), None);
        assert_eq!(FormatSniffer::container(&[]), None);
    }

    #[test]
    fn a_protected_audiobook_is_its_own_refusal() {
        let mut aax = vec![0, 0, 0, 0x20];
        aax.extend_from_slice(b"ftypaax ");
        assert_eq!(
            FormatSniffer::container(&aax),
            Some(Container::ProtectedAudiobook)
        );
        let mut m4a = vec![0, 0, 0, 0x20];
        m4a.extend_from_slice(b"ftypM4A ");
        assert_eq!(FormatSniffer::container(&m4a), Some(Container::Mp4));
        assert!(Container::ProtectedAudiobook.is_audio());
        assert!(!Container::Zip.is_audio());
    }

    #[test]
    fn every_refusal_is_named() {
        for container in [
            Container::Zip,
            Container::Rar,
            Container::SevenZip,
            Container::Pdf,
            Container::Tar,
        ] {
            assert!(!container.display_name().is_empty());
        }
        assert_eq!(Container::SevenZip.display_name(), "7-Zip");
    }
}
