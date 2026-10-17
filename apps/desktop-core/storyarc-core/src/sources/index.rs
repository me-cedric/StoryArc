//! Turns a file into a `Publication`. Mirrored from `PublicationIndexer.swift` and its
//! `+Building` file: the seam between the format layer and the library.
//!
//! Metadata has a precedence, and it is the whole point of the type. Embedded metadata
//! beats a guess from the filename, field by field, and both record where they came from
//! so an authoritative source can replace them later without raising a conflict the app
//! invented (`publication-formats`).

use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use sha2::{Digest, Sha256};

use crate::domain::{
    MetadataOrigin, Publication, PublicationFormat, PublicationIdentity, ReadingDirection,
    StreamingCapability, Timestamp,
};
use crate::formats::{
    ComicArchive, ComicArchiveError, ComicInfo, Container, EpubReader, FilenameMetadata,
    FormatSniffer, ImageFolderArchive,
};
use crate::io::{FileSource, RandomAccessSource, SourceError};

/// What went wrong, as a closed set of cases. A case, never a sentence: the apps word
/// these in the reader's language, and a string written here would reach no catalogue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IndexError {
    /// A container StoryArc recognises and does not read, named.
    Unsupported(String),
    /// Nothing at the path the library was handed.
    NotThere,
    /// Bytes no sniffer claims.
    FormatNotRecognised,
    /// The archive opened and asked for a password.
    ArchivePasswordProtected,
    /// The archive is one StoryArc reads and this one will not open.
    ArchiveUnreadable,
    /// Audio behind a store's content protection. Carries nothing: there is no key to ask
    /// for, and StoryArc does not circumvent a content protection.
    ContentProtected,
    /// The read was abandoned because its cancel token fired.
    Cancelled,
}

impl std::fmt::Display for IndexError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Unsupported(format) => write!(f, "{format} is not supported"),
            Self::NotThere => f.write_str("the file is not there"),
            Self::FormatNotRecognised => f.write_str("the format was not recognised"),
            Self::ArchivePasswordProtected => f.write_str("the archive is password protected"),
            Self::ArchiveUnreadable => f.write_str("the archive cannot be read"),
            Self::ContentProtected => f.write_str("the file is protected by a store"),
            Self::Cancelled => f.write_str("cancelled"),
        }
    }
}

impl std::error::Error for IndexError {}

/// How many bytes at each end of a publication the digest reads: 512 KB, as the mobile
/// apps read (ADR-0006, corrected 2026-08-31). Not the number in the ADR's prose, because
/// the digest string carries no scheme tag and every digest already written depends on it.
const DIGEST_WINDOW: usize = 512 * 1024;

pub struct PublicationIndexer;

impl PublicationIndexer {
    /// Indexes one local publication: a file or a folder. Opens the container, so it costs
    /// one read of the index, the digest's two ranged reads and one of `ComicInfo.xml`;
    /// never the whole file.
    ///
    /// `series_hint` is the name of the folder the file sits in, when that folder is a
    /// subfolder of a picked library rather than the library itself (`local-library`:
    /// a subfolder is "a series whose name is the folder name"). Embedded metadata and the
    /// filename both beat it.
    pub fn index_path(path: &Path, series_hint: Option<&str>) -> Result<Publication, IndexError> {
        let metadata = std::fs::metadata(path).map_err(|_| IndexError::NotThere)?;
        if metadata.is_dir() {
            return Self::folder(path);
        }
        let filename = file_name(path);
        let fallback = FilenameMetadata::new(&filename, series_hint, None);
        let source: Arc<dyn RandomAccessSource> =
            Arc::new(FileSource::open(path).map_err(|_| IndexError::NotThere)?);
        let identity = PublicationIdentity {
            server_identifier: None,
            content_digest: Self::content_digest(source.as_ref()).ok(),
            normalized_path: Some(normalized_path(path)),
        };
        let probe = source
            .read(0, FormatSniffer::PROBE_LENGTH)
            .map_err(source_error)?;
        let container = FormatSniffer::container(&probe).ok_or(IndexError::FormatNotRecognised)?;

        let mut publication = match container {
            Container::Pdf => {
                // The PDF reader is wave 4 (design.md, Decision 7): until then a PDF is a
                // record the library lists and the reader opens later, with no page count.
                let mut record =
                    Self::record(PublicationFormat::Pdf, identity, &filename, &fallback);
                record.streaming = StreamingCapability::Streams;
                record.display_title = fallback.series.clone().unwrap_or_else(|| filename.clone());
                record
            }
            Container::Zip => {
                // An EPUB is a ZIP too, and only its contents tell the two apart.
                match EpubReader::open(Arc::clone(&source)) {
                    Ok(epub) => Self::book(&epub, identity, &filename, &fallback),
                    Err(_) => Self::comic_file(
                        path,
                        PublicationFormat::Cbz,
                        identity,
                        &filename,
                        &fallback,
                    )?,
                }
            }
            Container::Tar => {
                Self::comic_file(path, PublicationFormat::Cbt, identity, &filename, &fallback)?
            }
            Container::Rar => {
                Self::comic_file(path, PublicationFormat::Cbr, identity, &filename, &fallback)?
            }
            Container::SevenZip => {
                return Err(IndexError::Unsupported(
                    PublicationFormat::Cb7.display_name().to_owned(),
                ));
            }
            Container::Mp4 | Container::Mp3 | Container::Flac | Container::Ogg => {
                // The audio reader is wave 4: a record with the container's own format.
                let format = match container {
                    Container::Mp4 => PublicationFormat::M4b,
                    Container::Mp3 => PublicationFormat::Mp3,
                    Container::Flac => PublicationFormat::Flac,
                    _ => PublicationFormat::Ogg,
                };
                let mut record = Self::record(format, identity, &filename, &fallback);
                record.streaming = StreamingCapability::Streams;
                record
            }
            Container::ProtectedAudiobook => return Err(IndexError::ContentProtected),
        };
        Self::stamp_file_facts(&mut publication, &metadata);
        Ok(publication)
    }

    /// A content digest for one publication: SHA-256 over the source's length as eight
    /// little-endian bytes, its first 512 KB and its last 512 KB — the tail omitted when the
    /// source is no longer than the window. The same bytes the mobile apps hash, so the hex
    /// agrees across platforms.
    pub fn content_digest(source: &dyn RandomAccessSource) -> Result<String, SourceError> {
        let mut hasher = Sha256::new();
        hasher.update(source.length().to_le_bytes());
        hasher.update(source.read(0, DIGEST_WINDOW)?);
        if source.length() > DIGEST_WINDOW as u64 {
            let (tail, _) = source.read_tail(DIGEST_WINDOW)?;
            hasher.update(tail);
        }
        Ok(hasher
            .finalize()
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect())
    }

    /// A publication that exists but whose pages cannot be reached from here yet. The
    /// library lists it and says why, rather than dropping it.
    fn record(
        format: PublicationFormat,
        identity: PublicationIdentity,
        filename: &str,
        fallback: &FilenameMetadata,
    ) -> Publication {
        let mut publication = Publication::new(
            identity,
            format,
            Self::title(None, fallback, filename),
            MetadataOrigin::Inferred,
        );
        publication.series = fallback.series.clone();
        publication.number = fallback.number.clone();
        publication.volume = fallback.volume;
        publication.year = fallback.year;
        publication.streaming = StreamingCapability::DownloadOnly;
        publication
    }

    fn comic_file(
        path: &Path,
        format: PublicationFormat,
        identity: PublicationIdentity,
        filename: &str,
        fallback: &FilenameMetadata,
    ) -> Result<Publication, IndexError> {
        let archive = match ComicArchive::open_file(path) {
            Ok(archive) => archive,
            // Readable as a *record* even though it cannot be opened: the library should
            // list it and say why, not silently drop it.
            Err(ComicArchiveError::SolidArchive) => {
                let mut refused = Self::record(format, identity, filename, fallback);
                refused.streaming = StreamingCapability::Refused;
                return Ok(refused);
            }
            Err(ComicArchiveError::PasswordProtected) => {
                return Err(IndexError::ArchivePasswordProtected);
            }
            Err(ComicArchiveError::UnsupportedContainer(container)) => {
                return Err(IndexError::Unsupported(container.display_name().to_owned()));
            }
            Err(ComicArchiveError::Cancelled) => return Err(IndexError::Cancelled),
            Err(_) => return Err(IndexError::ArchiveUnreadable),
        };
        let streaming = match &archive {
            ComicArchive::Rar(rar) if !(rar.is_streamable && !rar.is_download_only) => {
                StreamingCapability::DownloadOnly
            }
            _ => StreamingCapability::Streams,
        };
        Ok(Self::comic(
            archive.comic_info(),
            archive.pages().len(),
            archive.skipped_page_count(),
            archive.cover_page().map(|page| page.path.clone()),
            streaming,
            None,
            format,
            identity,
            filename,
            fallback,
        ))
    }

    /// A folder: an audiobook when its parts are audio, a comic otherwise.
    fn folder(path: &Path) -> Result<Publication, IndexError> {
        let name = file_name(path);
        let identity = PublicationIdentity::path(normalized_path(path));
        let fallback = FilenameMetadata::new(&name, None, None);
        let names: Vec<String> = std::fs::read_dir(path)
            .map_err(|_| IndexError::NotThere)?
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().into_owned())
            .collect();
        if is_audio_folder(&names) {
            let mut record =
                Self::record(PublicationFormat::AudioFolder, identity, &name, &fallback);
            record.streaming = StreamingCapability::Streams;
            return Ok(record);
        }
        let archive = ImageFolderArchive::open(path).map_err(|_| IndexError::ArchiveUnreadable)?;
        let mut publication = Self::comic(
            archive.comic_info.as_ref(),
            archive.pages.len(),
            archive.skipped_page_count,
            archive.cover_page().map(|page| page.path.clone()),
            StreamingCapability::Streams,
            // An unpacked folder is not one file, so nothing outside can weigh it: what it
            // occupies is what its pages add up to.
            Some(archive.byte_count()),
            PublicationFormat::ImageFolder,
            identity,
            &name,
            &fallback,
        );
        if let Ok(metadata) = std::fs::metadata(path) {
            publication.modified_at = metadata.modified().ok().map(Timestamp::from_system_time);
            publication.added_at = metadata
                .created()
                .ok()
                .or_else(|| metadata.modified().ok())
                .map(Timestamp::from_system_time);
        }
        Ok(publication)
    }

    #[allow(clippy::too_many_arguments)]
    fn comic(
        info: Option<&ComicInfo>,
        page_count: usize,
        skipped_page_count: usize,
        cover_path: Option<String>,
        streaming: StreamingCapability,
        file_size: Option<i64>,
        format: PublicationFormat,
        identity: PublicationIdentity,
        filename: &str,
        fallback: &FilenameMetadata,
    ) -> Publication {
        // Embedded metadata beats a filename guess, field by field rather than wholesale.
        let mut publication = Publication::new(
            identity,
            format,
            Self::title(info, fallback, filename),
            // Inferred unless *something* came out of the file itself.
            if info.is_some() {
                MetadataOrigin::Embedded
            } else {
                MetadataOrigin::Inferred
            },
        );
        publication.series = info
            .and_then(|i| i.series.clone())
            .or_else(|| fallback.series.clone());
        publication.number = info
            .and_then(|i| i.number.clone())
            .or_else(|| fallback.number.clone());
        publication.volume = info.and_then(|i| i.volume).or(fallback.volume);
        publication.authors = info.map(|i| i.writers.clone()).unwrap_or_default();
        publication.pencillers = info.map(|i| i.pencillers.clone()).unwrap_or_default();
        publication.publisher = info.and_then(|i| i.publisher.clone());
        publication.year = info.and_then(|i| i.year).or(fallback.year);
        publication.release_date = info.and_then(Self::release_date);
        publication.language = info.and_then(|i| i.language.clone());
        publication.summary = info.and_then(|i| i.summary.clone());
        publication.genres = info.map(|i| i.genres.clone()).unwrap_or_default();
        publication.tags = info.map(|i| i.tags.clone()).unwrap_or_default();
        publication.page_count = Some(page_count);
        publication.skipped_page_count = skipped_page_count;
        publication.cover_path = cover_path;
        publication.reading_direction = info
            .map(ComicInfo::reading_direction)
            .unwrap_or(ReadingDirection::LeftToRight);
        publication.streaming = streaming;
        publication.file_size = file_size;
        publication
    }

    fn book(
        epub: &EpubReader,
        identity: PublicationIdentity,
        filename: &str,
        fallback: &FilenameMetadata,
    ) -> Publication {
        let metadata = &epub.metadata;
        let mut publication = Publication::new(
            identity,
            PublicationFormat::Epub,
            metadata
                .title
                .clone()
                .or_else(|| fallback.series.clone())
                .unwrap_or_else(|| filename.to_owned()),
            if metadata.title.is_some() {
                MetadataOrigin::Embedded
            } else {
                MetadataOrigin::Inferred
            },
        );
        // The series the file declares, not its own title.
        publication.series = metadata.series.clone().or_else(|| fallback.series.clone());
        publication.number = metadata
            .series_index
            .clone()
            .or_else(|| fallback.number.clone());
        publication.volume = fallback.volume;
        publication.authors = metadata.author.clone().into_iter().collect();
        publication.publisher = metadata.publisher.clone();
        publication.year = fallback.year;
        publication.language = metadata.language.clone();
        publication.summary = metadata.description.clone();
        // The spine, not a page count: an EPUB's pages depend on the type size.
        publication.page_count = Some(epub.spine.len());
        publication.cover_path = epub.cover_or_spine_href();
        publication.reading_direction = ReadingDirection::inferred(
            match epub.page_progression_direction.as_deref() {
                Some("rtl") => Some(ReadingDirection::RightToLeft),
                Some("ltr") => Some(ReadingDirection::LeftToRight),
                _ => None,
            },
            metadata.language.as_deref(),
        );
        publication.is_fixed_layout = epub.is_fixed_layout;
        publication
    }

    /// `ComicInfo.xml`'s full publication date, when it names a month and a day as well as
    /// a year: midnight UTC on that date.
    fn release_date(info: &ComicInfo) -> Option<Timestamp> {
        let (year, month, day) = (info.year?, info.month?, info.day?);
        if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
            return None;
        }
        Some(Timestamp::from_civil(year, month as u32, day as u32))
    }

    /// What to show in a list: a title if the file states one, then series and number
    /// assembled, then the filename.
    fn title(info: Option<&ComicInfo>, fallback: &FilenameMetadata, filename: &str) -> String {
        if let Some(title) = info.and_then(|i| i.title.as_deref())
            && !title.is_empty()
        {
            return title.to_owned();
        }
        let series = info
            .and_then(|i| i.series.clone())
            .or_else(|| fallback.series.clone());
        let number = info
            .and_then(|i| i.number.clone())
            .or_else(|| fallback.number.clone());
        match (series, number) {
            (Some(series), Some(number)) => format!("{series} #{number}"),
            (Some(series), None) => series,
            (None, _) => filename.to_owned(),
        }
    }

    /// The two things about a publication that only the filesystem knows: its size, and
    /// when it arrived (creation date where the filesystem records one, modification
    /// otherwise).
    fn stamp_file_facts(publication: &mut Publication, metadata: &std::fs::Metadata) {
        publication.file_size = Some(metadata.len() as i64);
        publication.modified_at = metadata.modified().ok().map(Timestamp::from_system_time);
        publication.added_at = metadata
            .created()
            .ok()
            .or_else(|| metadata.modified().ok())
            .map(Timestamp::from_system_time);
    }
}

fn source_error(error: SourceError) -> IndexError {
    match error {
        SourceError::Cancelled => IndexError::Cancelled,
        _ => IndexError::ArchiveUnreadable,
    }
}

/// Audio extensions a folder's parts may carry, as `FolderKind.swift` lists them.
pub const AUDIO_EXTENSIONS: [&str; 11] = [
    "mp3", "m4a", "m4b", "aac", "flac", "opus", "ogg", "oga", "wav", "aiff", "aif",
];

/// Whether a folder's entries make it an audiobook rather than a comic: more audio parts
/// than images. A tie is a comic, which is what StoryArc has always made of a folder.
fn is_audio_folder(names: &[String]) -> bool {
    let mut images = 0;
    let mut audio = 0;
    for name in names {
        if !crate::formats::PageOrdering::is_candidate_entry(name) {
            continue;
        }
        let Some(extension) = crate::formats::PageOrdering::extension(name) else {
            continue;
        };
        if crate::formats::PageOrdering::IMAGE_EXTENSIONS.contains(&extension.as_str()) {
            images += 1;
        }
        if AUDIO_EXTENSIONS.contains(&extension.as_str()) {
            audio += 1;
        }
    }
    audio > images
}

pub(crate) fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// The form a publication's identity records a path in: absolute, with `.` and `..`
/// folded away, and no symbolic link resolved — the path the reader chose is the path the
/// record keeps, so a library on a linked volume keys the same way every launch.
pub fn normalized_path(path: &Path) -> String {
    let absolute = std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf());
    let mut folded = PathBuf::new();
    for component in absolute.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                folded.pop();
            }
            other => folded.push(other.as_os_str()),
        }
    }
    folded.to_string_lossy().into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::MemorySource;

    #[test]
    fn the_digest_hashes_the_length_the_head_and_the_tail() {
        // Three bytes: shorter than the window, so the tail is omitted and the hash is
        // over `len(8 LE) || bytes`.
        let digest =
            PublicationIndexer::content_digest(&MemorySource::new(b"abc".to_vec())).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(3u64.to_le_bytes());
        hasher.update(b"abc");
        let expected: String = hasher
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        assert_eq!(digest, expected);
        assert_eq!(digest.len(), 64);
    }

    #[test]
    fn the_digest_sees_both_ends_of_a_large_file_and_not_the_middle() {
        let mut bytes = vec![0u8; 3 * DIGEST_WINDOW];
        let before = PublicationIndexer::content_digest(&MemorySource::new(bytes.clone())).unwrap();
        bytes[DIGEST_WINDOW + 100] = 1;
        let middle = PublicationIndexer::content_digest(&MemorySource::new(bytes.clone())).unwrap();
        assert_eq!(before, middle, "the middle is not read, by design");
        bytes[3 * DIGEST_WINDOW - 1] = 1;
        let tail = PublicationIndexer::content_digest(&MemorySource::new(bytes)).unwrap();
        assert_ne!(before, tail);
    }

    #[test]
    fn a_title_is_the_stated_one_then_series_and_number_then_the_filename() {
        let fallback = FilenameMetadata::new("Saga 003 (2012).cbz", None, None);
        assert_eq!(PublicationIndexer::title(None, &fallback, "x"), "Saga #3");
        let info = ComicInfo {
            title: Some("Chapter One".into()),
            ..ComicInfo::default()
        };
        assert_eq!(
            PublicationIndexer::title(Some(&info), &fallback, "x"),
            "Chapter One"
        );
        let bare = FilenameMetadata::new("003.cbz", None, None);
        assert_eq!(PublicationIndexer::title(None, &bare, "003.cbz"), "003.cbz");
    }

    #[test]
    fn a_folder_of_parts_is_an_audiobook_only_by_majority() {
        assert!(is_audio_folder(&[
            "1.mp3".into(),
            "2.mp3".into(),
            "cover.jpg".into()
        ]));
        assert!(!is_audio_folder(&["1.mp3".into(), "p1.jpg".into()]));
        assert!(!is_audio_folder(&[".hidden.mp3".into()]));
    }

    #[test]
    fn a_path_is_folded_lexically_and_never_resolved() {
        let normalized = normalized_path(Path::new("/a/b/../c/./d.cbz"));
        assert!(normalized.ends_with("c/d.cbz") || normalized.ends_with("c\\d.cbz"));
        assert!(!normalized.contains(".."));
    }
}
