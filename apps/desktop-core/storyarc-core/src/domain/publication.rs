//! One thing a person can read: the library's unit. Mirrored from `Publication.swift` and
//! `PublicationFormat.swift`.
//!
//! Assembled by indexing a file — the format layer reads the container and its metadata,
//! and this is what comes out the other side, with no reference to how it was obtained.
//! Every field is durable, so the whole record is what the store keeps and what crosses the
//! seam as JSON (camelCase keys, as the mobile library documents spell theirs).

use serde::{Deserialize, Serialize};

use super::identity::PublicationIdentity;
use super::reading_direction::ReadingDirection;
use super::timestamp::Timestamp;

/// The container formats a publication can arrive in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PublicationFormat {
    Cbz,
    Cbr,
    Cb7,
    Cbt,
    Epub,
    Pdf,
    ImageFolder,
    M4b,
    Mp3,
    Flac,
    Ogg,
    AudioFolder,
}

impl PublicationFormat {
    pub const ALL: [Self; 12] = [
        Self::Cbz,
        Self::Cbr,
        Self::Cb7,
        Self::Cbt,
        Self::Epub,
        Self::Pdf,
        Self::ImageFolder,
        Self::M4b,
        Self::Mp3,
        Self::Flac,
        Self::Ogg,
        Self::AudioFolder,
    ];

    /// Whether pages are images rather than reflowable text.
    pub fn is_paged_images(self) -> bool {
        matches!(
            self,
            Self::Cbz | Self::Cbr | Self::Cb7 | Self::Cbt | Self::ImageFolder
        )
    }

    /// Whether a player rather than a reader opens this.
    pub fn is_audio(self) -> bool {
        matches!(
            self,
            Self::M4b | Self::Mp3 | Self::Flac | Self::Ogg | Self::AudioFolder
        )
    }

    /// Whether StoryArc can open a publication in this format today. CB7 is the one that
    /// parses as a format and does not open.
    pub fn is_openable(self) -> bool {
        self != Self::Cb7
    }

    /// How the format is named to a person — in a refusal, a filter, a detail row.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Cbz => "CBZ",
            Self::Cbr => "CBR",
            Self::Cb7 => "CB7",
            Self::Cbt => "CBT",
            Self::Epub => "EPUB",
            Self::Pdf => "PDF",
            Self::ImageFolder => "Folder",
            Self::M4b => "M4B",
            Self::Mp3 => "MP3",
            Self::Flac => "FLAC",
            Self::Ogg => "Ogg",
            Self::AudioFolder => "Audiobook folder",
        }
    }

    /// The format a media type names, when it names one this app can read. Parameters
    /// after a semicolon are ignored.
    pub fn from_media_type(media_type: &str) -> Option<Self> {
        let bare = media_type
            .split(';')
            .next()
            .unwrap_or_default()
            .trim()
            .to_lowercase();
        match bare.as_str() {
            "application/epub+zip" => Some(Self::Epub),
            "application/pdf" => Some(Self::Pdf),
            "application/vnd.comicbook+zip" | "application/x-cbz" => Some(Self::Cbz),
            "application/vnd.comicbook-rar" | "application/x-cbr" => Some(Self::Cbr),
            "application/vnd.comicbook+tar" | "application/x-cbt" => Some(Self::Cbt),
            "application/vnd.comicbook+7z" | "application/x-cb7" => Some(Self::Cb7),
            "audio/mp4" | "audio/m4b" | "audio/x-m4b" | "audio/m4a" | "audio/x-m4a"
            | "audio/aac" | "audio/aacp" => Some(Self::M4b),
            "audio/mpeg" | "audio/mp3" | "audio/x-mp3" | "audio/mpeg3" => Some(Self::Mp3),
            "audio/flac" | "audio/x-flac" => Some(Self::Flac),
            "audio/ogg" | "audio/x-ogg" | "audio/opus" | "audio/vorbis" => Some(Self::Ogg),
            _ => None,
        }
    }

    /// The media type that names this format. `None` for a folder, which is not a file.
    pub fn media_type(self) -> Option<&'static str> {
        match self {
            Self::Cbz => Some("application/vnd.comicbook+zip"),
            Self::Cbr => Some("application/vnd.comicbook-rar"),
            Self::Cb7 => Some("application/vnd.comicbook+7z"),
            Self::Cbt => Some("application/vnd.comicbook+tar"),
            Self::Epub => Some("application/epub+zip"),
            Self::Pdf => Some("application/pdf"),
            Self::ImageFolder | Self::AudioFolder => None,
            Self::M4b => Some("audio/mp4"),
            Self::Mp3 => Some("audio/mpeg"),
            Self::Flac => Some("audio/flac"),
            Self::Ogg => Some("audio/ogg"),
        }
    }
}

/// Whether a publication can be read without transferring all of it. Three states, not
/// two: a format that streams, one that must be downloaded first, and one that cannot be
/// read at all.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum StreamingCapability {
    Streams,
    DownloadOnly,
    Refused,
}

/// Where a value came from, which decides whether it may be silently replaced.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MetadataOrigin {
    Embedded,
    Inferred,
    Authoritative,
}

impl MetadataOrigin {
    /// Whether a value from `other` may replace one from `self` without asking.
    pub fn yields_to(self, other: Self) -> bool {
        self.rank() < other.rank()
    }

    fn rank(self) -> u8 {
        match self {
            Self::Inferred => 0,
            Self::Embedded => 1,
            Self::Authoritative => 2,
        }
    }
}

/// Where a series is in its own life, as a source reports it or a reader sets it by hand.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PublicationStatus {
    Ongoing,
    Hiatus,
    Completed,
    Cancelled,
    Ended,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Publication {
    /// Stable across sources, so the same book from a folder and from a server is one
    /// book with one reading position (ADR-0006).
    pub identity: PublicationIdentity,
    pub format: PublicationFormat,
    /// The title if it has one, else the series and number, else the filename.
    pub display_title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub series: Option<String>,
    /// Issue or chapter. A string: "3.5" and "Annual 1" are both real.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub number: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub volume: Option<i64>,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub pencillers: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publisher: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub year: Option<i64>,
    /// Midnight UTC on the full publication date, when `ComicInfo.xml` names one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub release_date: Option<Timestamp>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default)]
    pub genres: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<PublicationStatus>,
    pub origin: MetadataOrigin,
    /// Pages for a comic, spine items for an EPUB. `None` when the publication could not
    /// be indexed deeply enough to know.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub page_count: Option<usize>,
    /// Entries that looked like pages and could not be read.
    #[serde(default)]
    pub skipped_page_count: usize,
    /// The path of the cover *inside* the publication, when it has one.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cover_path: Option<String>,
    pub reading_direction: ReadingDirection,
    #[serde(default)]
    pub is_fixed_layout: bool,
    pub streaming: StreamingCapability,
    /// Which source this came from, when the app knows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_id: Option<String>,
    /// How much disk the publication occupies, when the walk that found it asked.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_size: Option<i64>,
    /// When the file was last written, as the filesystem reports it: half of the
    /// reconcile `local-library` asks for.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub modified_at: Option<Timestamp>,
    /// When the file arrived where the app found it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub added_at: Option<Timestamp>,
}

impl Publication {
    /// The smallest honest record: an identity, a format and a title, with every other
    /// field absent. Callers fill in what they know.
    pub fn new(
        identity: PublicationIdentity,
        format: PublicationFormat,
        display_title: impl Into<String>,
        origin: MetadataOrigin,
    ) -> Self {
        Self {
            identity,
            format,
            display_title: display_title.into(),
            series: None,
            number: None,
            volume: None,
            authors: Vec::new(),
            pencillers: Vec::new(),
            publisher: None,
            year: None,
            release_date: None,
            language: None,
            summary: None,
            genres: Vec::new(),
            tags: Vec::new(),
            status: None,
            origin,
            page_count: None,
            skipped_page_count: 0,
            cover_path: None,
            reading_direction: ReadingDirection::LeftToRight,
            is_fixed_layout: false,
            streaming: StreamingCapability::Streams,
            source_id: None,
            file_size: None,
            modified_at: None,
            added_at: None,
        }
    }

    /// A stable key for lists and diffing: `PublicationIdentity::stable_id`.
    pub fn id(&self) -> String {
        self.identity.stable_id()
    }

    /// Whether the reader can open this at all. False only for `Refused`.
    pub fn is_openable(&self) -> bool {
        self.streaming != StreamingCapability::Refused
    }

    /// Whether this publication still describes the file on disk. Unknown facts mean
    /// *not* unchanged: a publication indexed before these were recorded is re-read.
    pub fn matches_file(&self, size: Option<i64>, modified_at: Option<Timestamp>) -> bool {
        match (self.file_size, self.modified_at, size, modified_at) {
            (Some(mine), Some(my_moment), Some(size), Some(moment)) => {
                mine == size && my_moment == moment
            }
            _ => false,
        }
    }

    /// Whether some pages are missing from what the reader will show.
    pub fn is_partial(&self) -> bool {
        self.skipped_page_count > 0
    }

    /// Whether the text in this publication reflows: an EPUB that is not fixed-layout.
    pub fn is_reflowable(&self) -> bool {
        self.format == PublicationFormat::Epub && !self.is_fixed_layout
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_media_type_names_a_format_with_its_parameters_ignored() {
        assert_eq!(
            PublicationFormat::from_media_type("application/epub+zip;charset=utf-8"),
            Some(PublicationFormat::Epub)
        );
        assert_eq!(
            PublicationFormat::from_media_type("audio/x-m4b"),
            Some(PublicationFormat::M4b)
        );
        assert_eq!(PublicationFormat::from_media_type("text/plain"), None);
        for format in PublicationFormat::ALL {
            if let Some(media_type) = format.media_type() {
                assert_eq!(PublicationFormat::from_media_type(media_type), Some(format));
            }
        }
    }

    #[test]
    fn cb7_is_the_one_format_that_parses_and_does_not_open() {
        assert!(!PublicationFormat::Cb7.is_openable());
        assert!(PublicationFormat::Cbr.is_openable());
        assert_eq!(PublicationFormat::Cb7.display_name(), "CB7");
    }

    #[test]
    fn an_inferred_value_yields_to_anything_and_an_authoritative_one_to_nothing() {
        assert!(MetadataOrigin::Inferred.yields_to(MetadataOrigin::Embedded));
        assert!(MetadataOrigin::Embedded.yields_to(MetadataOrigin::Authoritative));
        assert!(!MetadataOrigin::Authoritative.yields_to(MetadataOrigin::Embedded));
    }

    #[test]
    fn a_file_matches_only_when_both_facts_are_known_and_equal() {
        let mut publication = Publication::new(
            PublicationIdentity::path("/a.cbz"),
            PublicationFormat::Cbz,
            "A",
            MetadataOrigin::Inferred,
        );
        assert!(!publication.matches_file(Some(10), Some(Timestamp(5))));
        publication.file_size = Some(10);
        publication.modified_at = Some(Timestamp(5));
        assert!(publication.matches_file(Some(10), Some(Timestamp(5))));
        assert!(!publication.matches_file(Some(11), Some(Timestamp(5))));
        assert!(!publication.matches_file(Some(10), None));
    }

    #[test]
    fn the_wire_shape_is_camel_case_and_round_trips() {
        let publication = Publication::new(
            PublicationIdentity::path("/a.cbz"),
            PublicationFormat::ImageFolder,
            "A",
            MetadataOrigin::Embedded,
        );
        let json = serde_json::to_string(&publication).unwrap();
        assert!(json.contains(r#""format":"imageFolder""#));
        assert!(json.contains(r#""displayTitle":"A""#));
        assert!(json.contains(r#""readingDirection":"leftToRight""#));
        assert_eq!(
            serde_json::from_str::<Publication>(&json).unwrap(),
            publication
        );
    }
}
