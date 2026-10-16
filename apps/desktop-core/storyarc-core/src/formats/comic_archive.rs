//! Reading pages out of a comic archive. Mirrored from `ComicArchive.swift` and
//! `RarComicArchive.swift`.
//!
//! `publication-formats` requires a corrupt archive to yield whatever pages can be read
//! plus a count of what was skipped, rather than refusing the whole publication. And it
//! requires a refusal to be *named*: there are four distinct refusals here and they are
//! not interchangeable.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::comic_info::ComicInfo;
use super::page_ordering::{CoverSelection, PageDeclarations, PageEntry, PageOrdering};
use super::rar::{RarEntry, RarError, RarGeneration, RarReader};
use super::rar_decoder::{DecodeError, RarDecoder};
use super::sniff::{Container, FormatSniffer};
use super::tar::{TarEntry, TarError, TarReader};
use super::zip::{ZipEntry, ZipError, ZipReader};
use crate::io::{FileSource, RandomAccessSource, SourceError};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ComicArchiveError {
    /// The container is one StoryArc recognises but cannot read yet.
    UnsupportedContainer(Container),
    /// Nothing recognisable at all.
    UnrecognisedContainer,
    /// The archive needs a password. `publication-formats` requires StoryArc to say so
    /// rather than prompt, because it does not manage archive passwords.
    PasswordProtected,
    /// Not a single entry could be read, damaged beyond partial recovery.
    Unreadable,
    /// A solid archive that cannot be read at all. Named separately from
    /// `UnsupportedContainer` because the container *is* supported and this particular
    /// file still cannot be read. Solid RAR4 only: libarchive reads a solid RAR5 completely.
    SolidArchive,
    /// The read was abandoned because its cancel token fired. Not damage.
    Cancelled,
    /// A compressed RAR page could not be decoded.
    Decode(DecodeError),
}

impl std::fmt::Display for ComicArchiveError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedContainer(container) => {
                write!(f, "{} archives are not supported", container.display_name())
            }
            Self::UnrecognisedContainer => f.write_str("unrecognised container"),
            Self::PasswordProtected => f.write_str("the archive is password protected"),
            Self::Unreadable => f.write_str("the archive cannot be read"),
            Self::SolidArchive => {
                f.write_str("this comic uses solid compression, which cannot be opened")
            }
            Self::Cancelled => f.write_str("cancelled"),
            Self::Decode(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for ComicArchiveError {}

impl From<SourceError> for ComicArchiveError {
    fn from(error: SourceError) -> Self {
        match error {
            SourceError::Cancelled => Self::Cancelled,
            _ => Self::Unreadable,
        }
    }
}

impl From<ZipError> for ComicArchiveError {
    fn from(error: ZipError) -> Self {
        match error {
            ZipError::Encrypted => Self::PasswordProtected,
            ZipError::Source(source) => source.into(),
            _ => Self::Unreadable,
        }
    }
}

impl From<TarError> for ComicArchiveError {
    fn from(error: TarError) -> Self {
        match error {
            TarError::NotTar => Self::UnrecognisedContainer,
            TarError::Source(source) => source.into(),
            TarError::Malformed(_) => Self::Unreadable,
        }
    }
}

impl From<RarError> for ComicArchiveError {
    fn from(error: RarError) -> Self {
        match error {
            RarError::NotRar => Self::UnrecognisedContainer,
            RarError::Source(source) => source.into(),
            _ => Self::Unreadable,
        }
    }
}

impl From<DecodeError> for ComicArchiveError {
    fn from(error: DecodeError) -> Self {
        Self::Decode(error)
    }
}

/// The pages of a comic container, whatever the container.
pub enum ComicArchive {
    Zip(ZipComicArchive),
    Tar(TarComicArchive),
    Rar(RarComicArchive),
}

impl ComicArchive {
    /// Sniffs the container, then opens it. The extension is never trusted.
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, ComicArchiveError> {
        let probe = source.read(0, FormatSniffer::PROBE_LENGTH)?;
        match FormatSniffer::container(&probe).ok_or(ComicArchiveError::UnrecognisedContainer)? {
            Container::Zip => Ok(Self::Zip(ZipComicArchive::open(source)?)),
            Container::Tar => Ok(Self::Tar(TarComicArchive::open(source)?)),
            // No path here: a non-solid archive decodes each compressed page from its own
            // ranged bytes, and a solid one needs the file-based entry point below.
            Container::Rar => Ok(Self::Rar(RarComicArchive::open(source, None)?)),
            // `publication-formats` requires a *named* refusal, never a generic parse
            // failure. 7-Zip is out of scope, PDF has its own reader, and audio is not an
            // archive at all — naming it here is where the player will take over.
            other => Err(ComicArchiveError::UnsupportedContainer(other)),
        }
    }

    /// Opens a local file. A local RAR gets its path, which is what lets libarchive
    /// decompress a page of a solid archive; every other container reads through the
    /// source alone.
    pub fn open_file(path: impl AsRef<Path>) -> Result<Self, ComicArchiveError> {
        let path = path.as_ref();
        let source: Arc<dyn RandomAccessSource> = Arc::new(FileSource::open(path)?);
        let probe = source.read(0, FormatSniffer::PROBE_LENGTH)?;
        if FormatSniffer::container(&probe) == Some(Container::Rar) {
            return Ok(Self::Rar(RarComicArchive::open(
                source,
                Some(path.to_path_buf()),
            )?));
        }
        Self::open(source)
    }

    pub fn pages(&self) -> &[PageEntry] {
        match self {
            Self::Zip(a) => &a.pages,
            Self::Tar(a) => &a.pages,
            Self::Rar(a) => &a.pages,
        }
    }

    /// Entries that looked like pages but could not be read.
    pub fn skipped_page_count(&self) -> usize {
        match self {
            Self::Zip(a) => a.skipped_page_count,
            Self::Tar(a) => a.skipped_page_count,
            Self::Rar(a) => a.skipped_page_count,
        }
    }

    /// The archive's parsed metadata, when it carries any.
    pub fn comic_info(&self) -> Option<&ComicInfo> {
        match self {
            Self::Zip(a) => a.comic_info.as_ref(),
            Self::Tar(a) => a.comic_info.as_ref(),
            Self::Rar(a) => a.comic_info.as_ref(),
        }
    }

    /// Raw bytes for one page.
    pub fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        match self {
            Self::Zip(a) => a.data(page),
            Self::Tar(a) => a.data(page),
            Self::Rar(a) => a.data(page),
        }
    }

    /// The page to show as the publication's cover: the first page in reading order,
    /// *unless* `ComicInfo.xml` designates a different one.
    pub fn cover_page(&self) -> Option<&PageEntry> {
        CoverSelection::cover(
            self.pages(),
            self.comic_info().and_then(|info| info.cover_page_index),
        )
    }

    /// Pages the container declares as double-page spreads.
    pub fn double_page_indices(&self) -> Vec<usize> {
        let declared = self
            .comic_info()
            .map(|info| info.double_page_indices.as_slice())
            .unwrap_or_default();
        PageDeclarations::spreads(self.pages(), declared)
    }

    /// Pages the container declares as the start of a chapter.
    pub fn chapter_start_indices(&self) -> Vec<usize> {
        let declared = self
            .comic_info()
            .map(|info| info.chapter_start_indices.as_slice())
            .unwrap_or_default();
        PageDeclarations::chapter_starts(self.pages(), declared)
    }

    /// The chapter's own name, by the page it starts at.
    pub fn chapter_titles(&self) -> HashMap<usize, String> {
        self.comic_info()
            .map(|info| info.chapter_titles.clone())
            .unwrap_or_default()
    }
}

fn is_comic_info(path: &str) -> bool {
    path.to_lowercase().ends_with("comicinfo.xml")
}

/// A CBZ, or anything else that turns out to be a ZIP — including a file named `.cbr`
/// that is really a ZIP, which the format spec requires to open.
pub struct ZipComicArchive {
    pub pages: Vec<PageEntry>,
    pub skipped_page_count: usize,
    /// `ComicInfo.xml` contents when the archive carries one.
    pub comic_info_data: Option<Vec<u8>>,
    pub comic_info: Option<ComicInfo>,
    /// True when the archive's index was rebuilt by scanning, because its central
    /// directory was gone. The pages are real; the count may be short.
    pub is_recovered: bool,
    reader: ZipReader,
    path_to_entry: HashMap<String, ZipEntry>,
}

impl ZipComicArchive {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, ComicArchiveError> {
        let reader = match ZipReader::open(Arc::clone(&source)) {
            Ok(reader) => reader,
            // A ZIP whose central directory is gone — a truncated download, a partial
            // copy. `publication-formats` requires opening whatever can be read rather
            // than refusing the publication, and owning the reader is what makes that
            // possible (ADR-0008).
            Err(ZipError::NoCentralDirectory) => {
                ZipReader::recovering(source).map_err(|_| ComicArchiveError::Unreadable)?
            }
            Err(error) => return Err(error.into()),
        };
        let is_recovered = reader.is_recovered();

        let mut candidates = Vec::new();
        let mut skipped = 0;
        let mut comic_info_entry = None;
        let mut index = HashMap::new();

        for entry in reader.entries() {
            if is_comic_info(&entry.path) {
                comic_info_entry = Some(entry.clone());
                continue;
            }
            if !PageOrdering::is_page(&entry.path) {
                continue;
            }
            if entry.is_encrypted {
                // `publication-formats`: state that the archive is protected rather than
                // prompting. One encrypted page means the archive is.
                return Err(ComicArchiveError::PasswordProtected);
            }
            // A zero-length entry is a page that will never decode. Counting it as skipped
            // is what lets the reader say "opened 10, skipped 2". In a recovered archive a
            // zero *uncompressed* size means unknown rather than empty, so what matters
            // there is whether any bytes survived.
            let has_bytes = if is_recovered {
                entry.compressed_size > 0
            } else {
                entry.uncompressed_size > 0
            };
            if !has_bytes {
                skipped += 1;
                continue;
            }
            // A recovered entry's uncompressed size is often unknown, so the compressed
            // size stands in: a lower bound on the page, better than zero for a placeholder.
            let byte_count = if entry.uncompressed_size > 0 {
                entry.uncompressed_size
            } else {
                entry.compressed_size
            };
            candidates.push(PageEntry::new(entry.path.clone(), Some(byte_count)));
            index.insert(entry.path.clone(), entry.clone());
        }

        let comic_info_data = match comic_info_entry {
            Some(entry) => Some(reader.data(&entry)?),
            None => None,
        };
        let comic_info = comic_info_data.as_deref().and_then(ComicInfo::parse);

        Ok(Self {
            pages: PageOrdering::sorted(candidates),
            skipped_page_count: skipped,
            comic_info_data,
            comic_info,
            is_recovered,
            reader,
            path_to_entry: index,
        })
    }

    pub fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        let entry = self
            .path_to_entry
            .get(&page.path)
            .ok_or(ComicArchiveError::Unreadable)?;
        Ok(self.reader.data(entry)?)
    }

    /// Every page's bytes, skipping any that fail. Used by the indexer, which needs a
    /// cover and cannot afford to abort on one bad entry.
    pub fn readable_data(&self, pages: &[PageEntry]) -> Vec<(PageEntry, Vec<u8>)> {
        pages
            .iter()
            .filter_map(|page| self.data(page).ok().map(|data| (page.clone(), data)))
            .collect()
    }
}

/// A CBT. TAR carries no compression and no encryption, so opening one is header parsing
/// and nothing else.
pub struct TarComicArchive {
    pub pages: Vec<PageEntry>,
    pub skipped_page_count: usize,
    pub comic_info_data: Option<Vec<u8>>,
    pub comic_info: Option<ComicInfo>,
    reader: TarReader,
    path_to_entry: HashMap<String, TarEntry>,
}

impl TarComicArchive {
    pub fn open(source: Arc<dyn RandomAccessSource>) -> Result<Self, ComicArchiveError> {
        let reader = TarReader::open(source)?;

        let mut candidates = Vec::new();
        let mut skipped = 0;
        let mut comic_info_entry = None;
        let mut index = HashMap::new();

        for entry in reader.entries() {
            if is_comic_info(&entry.path) {
                comic_info_entry = Some(entry.clone());
                continue;
            }
            if !PageOrdering::is_page(&entry.path) {
                continue;
            }
            if entry.size == 0 {
                skipped += 1;
                continue;
            }
            candidates.push(PageEntry::new(entry.path.clone(), Some(entry.size)));
            index.insert(entry.path.clone(), entry.clone());
        }

        let comic_info_data = match comic_info_entry {
            Some(entry) => Some(reader.data(&entry)?),
            None => None,
        };
        let comic_info = comic_info_data.as_deref().and_then(ComicInfo::parse);

        Ok(Self {
            pages: PageOrdering::sorted(candidates),
            skipped_page_count: skipped,
            comic_info_data,
            comic_info,
            reader,
            path_to_entry: index,
        })
    }

    pub fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        let entry = self
            .path_to_entry
            .get(&page.path)
            .ok_or(ComicArchiveError::Unreadable)?;
        Ok(self.reader.data(entry)?)
    }
}

/// A CBR.
///
/// Indexes on headers alone: `RarReader` parses names, sizes and flags without a decoder,
/// so a remote CBR is catalogued without downloading it. Reading a *compressed* page needs
/// `RarDecoder`, which is the only place libarchive is used.
///
/// Given a path, every compressed page decodes from the file. Without one — a remote
/// source not yet downloaded — a stored page reads by range, and a compressed page of a
/// non-solid archive decodes from its own ranged bytes (`RarReader::isolated`). Only a
/// solid archive needs the whole file: its compressed pages set `is_download_only` rather
/// than being dropped or failing the whole archive.
pub struct RarComicArchive {
    pub pages: Vec<PageEntry>,
    pub skipped_page_count: usize,
    pub generation: RarGeneration,
    pub comic_info_data: Option<Vec<u8>>,
    pub comic_info: Option<ComicInfo>,
    /// Whether pages can be read out of order from a remote source. False for a solid
    /// archive, which has to be decompressed from the start.
    pub is_streamable: bool,
    /// True when at least one listed page is compressed in a solid archive and there is no
    /// local file yet to hand to the decoder.
    pub is_download_only: bool,
    reader: RarReader,
    path_to_entry: HashMap<String, RarEntry>,
    /// Where the archive lives on disk, when it does. `None` means compressed entries of a
    /// solid archive cannot be decoded yet.
    file_path: Option<PathBuf>,
}

impl RarComicArchive {
    pub fn open(
        source: Arc<dyn RandomAccessSource>,
        file_path: Option<PathBuf>,
    ) -> Result<Self, ComicArchiveError> {
        let reader = RarReader::open(source)?;
        let generation = reader.generation();

        if reader.is_encrypted() {
            return Err(ComicArchiveError::PasswordProtected);
        }
        // Checked before the page list is built. For a solid RAR4 the first entry reads fine
        // and everything after it does not, so surfacing a one-page comic here would be a
        // lie. A solid RAR5 is readable once local, so it passes — `is_solid` is what marks
        // it non-streamable, separately.
        if !reader.is_readable_when_local() {
            return Err(ComicArchiveError::SolidArchive);
        }
        // No entries at all means the headers did not parse — a truncated or damaged file,
        // not an archive that happens to hold no images. The ZIP path draws the same line:
        // `no-pages.cbz` has entries and zero pages.
        if reader.entries().is_empty() {
            return Err(ComicArchiveError::Unreadable);
        }

        let mut candidates = Vec::new();
        let mut skipped = 0;
        let mut undecodable = 0;
        let mut index = HashMap::new();
        let comic_info_entry = reader
            .entries()
            .iter()
            .find(|entry| is_comic_info(&entry.path))
            .cloned();

        for entry in reader.entries() {
            if !PageOrdering::is_page(&entry.path) {
                continue;
            }
            // A zero-length entry never decodes to anything, local file or not.
            if entry.size == 0 {
                skipped += 1;
                continue;
            }
            // A compressed entry of a solid archive is readable only with a local file to
            // hand to libarchive. Without one it is still a real page: it is listed from the
            // header, and the archive flags itself as download-only.
            if !entry.is_stored && file_path.is_none() && reader.is_solid() {
                undecodable += 1;
            }
            candidates.push(PageEntry::new(entry.path.clone(), Some(entry.size)));
            index.insert(entry.path.clone(), entry.clone());
        }

        // `ComicInfo.xml`'s raw bytes, read like a page — `None` when it cannot be read,
        // which in index-only mode is a compressed entry of a solid archive.
        let comic_info_data = comic_info_entry
            .and_then(|entry| Self::entry_data(&entry, &reader, file_path.as_deref()).ok());
        let comic_info = comic_info_data.as_deref().and_then(ComicInfo::parse);

        Ok(Self {
            pages: PageOrdering::sorted(candidates),
            skipped_page_count: skipped,
            generation,
            comic_info_data,
            comic_info,
            is_streamable: !reader.is_solid(),
            is_download_only: undecodable > 0,
            reader,
            path_to_entry: index,
            file_path,
        })
    }

    /// One entry's bytes: by range when stored, from the file when there is one, and from
    /// the entry's own ranged bytes when the archive is not solid.
    fn entry_data(
        entry: &RarEntry,
        reader: &RarReader,
        file_path: Option<&Path>,
    ) -> Result<Vec<u8>, ComicArchiveError> {
        if entry.is_stored {
            return Ok(reader.data(entry)?);
        }
        if let Some(path) = file_path {
            return Ok(RarDecoder::data_for_entry(&entry.path, path)?);
        }
        if reader.is_solid() {
            return Err(ComicArchiveError::UnsupportedContainer(Container::Rar));
        }
        Ok(RarDecoder::data_of_isolated(
            &entry.path,
            reader.isolated(entry)?,
        )?)
    }

    pub fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        let entry = self
            .path_to_entry
            .get(&page.path)
            .ok_or(ComicArchiveError::Unreadable)?;
        Self::entry_data(entry, &self.reader, self.file_path.as_deref())
    }

    /// Every listed page's bytes in one pass over the archive.
    ///
    /// For a solid archive this is the only affordable shape: reading page 30 there means
    /// decompressing 1 to 29, so asking page by page would be quadratic. The indexer wants
    /// this anyway — it needs a cover and a spread check, not one page.
    pub fn all_page_data(&self) -> Result<HashMap<String, Vec<u8>>, ComicArchiveError> {
        let Some(path) = &self.file_path else {
            return Ok(HashMap::new());
        };
        let wanted: HashSet<String> = self.pages.iter().map(|p| p.path.clone()).collect();
        Ok(RarDecoder::data_for_entries(&wanted, path)?)
    }
}
