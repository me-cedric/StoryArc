//! The operations a desktop app calls, in one place: open a folder source and list its
//! publications, open a publication and read its pages, and keep the reader's place.
//!
//! The Linux app calls these directly; the Windows app reaches the same functions through
//! `storyarc-ffi`, which adds nothing but the C types. Every call here is synchronous and
//! may touch the disk, so an app calls it off its interface thread.

use std::collections::HashMap;
use std::fmt;
use std::path::{Path, PathBuf};

use crate::domain::{Publication, PublicationFormat, PublicationIdentity, ReadingProgress};
use crate::formats::{ComicArchive, ComicArchiveError, ImageFolderArchive, PageEntry};
use crate::image::{self, DecodedPage, PageDecodeError, PageSize};
use crate::io::CancelToken;
use crate::sources::{FolderScan, IndexError, PublicationIndexer, ScanReport, SkippedFile};
use crate::store::{Store, StoreError};

/// Why a library call failed. Each case is one the app words for the reader.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LibraryError {
    /// Nothing at the path, or a folder where a file was expected and the reverse.
    NotFound(String),
    /// The publication could not be indexed: refused by name, protected or unreadable.
    Index(IndexError),
    /// The container opened and its pages could not be listed or read.
    Archive(ComicArchiveError),
    /// The publication is a kind this call does not page through yet: EPUB, PDF, audio.
    NotPaged(PublicationFormat),
    /// A page index at or past the publication's page count.
    PageOutOfRange { index: usize, count: usize },
    /// The page's bytes could not become pixels, with the codec named where it is known.
    Decode(PageDecodeError),
    /// The local store refused, or the disk is full.
    Store(StoreError),
}

impl fmt::Display for LibraryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NotFound(path) => write!(f, "nothing to open at {path}"),
            Self::Index(error) => write!(f, "{error}"),
            Self::Archive(error) => write!(f, "{error}"),
            Self::NotPaged(format) => write!(
                f,
                "{} publications are not opened page by page yet",
                format.display_name()
            ),
            Self::PageOutOfRange { index, count } => {
                write!(f, "page {index} asked of a publication of {count} pages")
            }
            Self::Decode(error) => write!(f, "{error}"),
            Self::Store(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for LibraryError {}

impl From<IndexError> for LibraryError {
    fn from(error: IndexError) -> Self {
        Self::Index(error)
    }
}

impl From<ComicArchiveError> for LibraryError {
    fn from(error: ComicArchiveError) -> Self {
        Self::Archive(error)
    }
}

impl From<PageDecodeError> for LibraryError {
    fn from(error: PageDecodeError) -> Self {
        Self::Decode(error)
    }
}

impl From<StoreError> for LibraryError {
    fn from(error: StoreError) -> Self {
        Self::Store(error)
    }
}

/// A folder the reader chose, scanned into publications.
///
/// Opening scans once; [`FolderSource::rescan`] reconciles by size and modification date
/// and opens only what changed (`local-library`).
pub struct FolderSource {
    scan: FolderScan,
    report: ScanReport,
}

impl FolderSource {
    /// Scans `root`. Costs one directory listing per folder and one container open per
    /// publication. The token stops the walk between files; what was found so far is kept.
    pub fn open(root: impl AsRef<Path>, cancel: &CancelToken) -> Result<Self, LibraryError> {
        let root = root.as_ref();
        if !root.is_dir() {
            return Err(LibraryError::NotFound(root.display().to_string()));
        }
        let scan = FolderScan::new(root);
        let report = scan.scan(|_| None, cancel);
        Ok(Self { scan, report })
    }

    /// Walks the folder again, reusing every publication whose file is unchanged, and
    /// returns what the walk did. A second scan of an unchanged folder opens nothing.
    pub fn rescan(&mut self, cancel: &CancelToken) -> ScanReport {
        let known: HashMap<String, Publication> = self
            .report
            .publications
            .iter()
            .filter_map(|publication| {
                let path = publication.identity.normalized_path.clone()?;
                Some((path, publication.clone()))
            })
            .collect();
        let report = self.scan.scan(
            |path| known.get(path.to_string_lossy().as_ref()).cloned(),
            cancel,
        );
        self.report = report.clone();
        report
    }

    /// The publications found, in walk order: depth first, natural order within a folder.
    pub fn publications(&self) -> &[Publication] {
        &self.report.publications
    }

    /// Files the walk recognised and did not index, each with its reason.
    pub fn skipped(&self) -> &[SkippedFile] {
        &self.report.skipped
    }

    /// Whether the last walk stopped because its token was raised. What it found before
    /// stopping is kept.
    pub fn was_cancelled(&self) -> bool {
        self.report.was_cancelled
    }

    /// Folders the walk could not list: the difference between an empty library and one
    /// whose access lapsed.
    pub fn unreadable_folders(&self) -> &[String] {
        &self.report.unreadable_folders
    }

    /// The publications as a UTF-8 JSON array of the records the phones write: camelCase
    /// fields, absent values left out.
    pub fn records_json(&self) -> String {
        serde_json::to_string(self.publications()).unwrap_or_else(|_| "[]".to_owned())
    }
}

impl fmt::Debug for FolderSource {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("FolderSource")
            .field("publications", &self.report.publications.len())
            .field("skipped", &self.report.skipped.len())
            .finish()
    }
}

/// Where an open publication's pages come from.
enum Pages {
    Archive(ComicArchive),
    Folder(ImageFolderArchive),
}

impl Pages {
    fn entries(&self) -> &[PageEntry] {
        match self {
            Self::Archive(archive) => archive.pages(),
            Self::Folder(folder) => &folder.pages,
        }
    }

    fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        match self {
            Self::Archive(archive) => archive.data(page),
            Self::Folder(folder) => folder.data(page),
        }
    }
}

/// A comic opened for reading: its record and its pages.
///
/// One thread at a time: a reader window keeps one and decodes on a worker.
pub struct OpenPublication {
    path: PathBuf,
    publication: Publication,
    pages: Pages,
}

impl OpenPublication {
    /// Opens a comic archive (CBZ, CBR, CBT) or a folder of images. Indexes it for its
    /// record, then lists its pages. EPUB, PDF and audio are refused with
    /// [`LibraryError::NotPaged`]; CB7 and protected audio are refused by name.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, LibraryError> {
        let path = path.as_ref();
        if !path.exists() {
            return Err(LibraryError::NotFound(path.display().to_string()));
        }
        let publication = PublicationIndexer::index_path(path, None)?;
        let pages = match publication.format {
            PublicationFormat::Cbz | PublicationFormat::Cbr | PublicationFormat::Cbt => {
                Pages::Archive(ComicArchive::open_file(path)?)
            }
            PublicationFormat::ImageFolder => Pages::Folder(ImageFolderArchive::open(path)?),
            other => return Err(LibraryError::NotPaged(other)),
        };
        Ok(Self {
            path: path.to_path_buf(),
            publication,
            pages,
        })
    }

    /// Where the publication was opened from.
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// The publication's record: title, series, number, authors, identity and the rest.
    pub fn publication(&self) -> &Publication {
        &self.publication
    }

    /// The record as UTF-8 JSON, the same shape as [`FolderSource::records_json`] uses.
    pub fn metadata_json(&self) -> String {
        serde_json::to_string(&self.publication).unwrap_or_else(|_| "{}".to_owned())
    }

    /// The number of pages, in reading order.
    pub fn page_count(&self) -> usize {
        self.pages.entries().len()
    }

    /// The pages the container declares as double-page spreads, by index.
    pub fn declared_spreads(&self) -> Vec<usize> {
        match &self.pages {
            Pages::Archive(archive) => archive.double_page_indices(),
            Pages::Folder(folder) => folder.double_page_indices(),
        }
    }

    /// One page's bytes as the archive holds them.
    pub fn page_bytes(&self, index: usize) -> Result<Vec<u8>, LibraryError> {
        let entries = self.pages.entries();
        let page = entries.get(index).ok_or(LibraryError::PageOutOfRange {
            index,
            count: entries.len(),
        })?;
        Ok(self.pages.data(page)?)
    }

    /// One page's size, read from its header without decoding it.
    pub fn page_size(&self, index: usize) -> Result<PageSize, LibraryError> {
        Ok(image::dimensions(&self.page_bytes(index)?)?)
    }

    /// One page decoded to RGBA, at most `max_pixel_size` on its longest edge when given.
    pub fn decode_page(
        &self,
        index: usize,
        max_pixel_size: Option<u32>,
    ) -> Result<DecodedPage, LibraryError> {
        Ok(image::decode(&self.page_bytes(index)?, max_pixel_size)?)
    }
}

impl fmt::Debug for OpenPublication {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("OpenPublication")
            .field("path", &self.path)
            .field("pages", &self.page_count())
            .finish()
    }
}

/// Where the reader's place is kept: the local store of ADR-0006, written first, always.
pub struct ProgressStore {
    store: Store,
}

impl ProgressStore {
    /// Opens or creates the store at `path`, usually `StorageLocations::store_file()`.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, LibraryError> {
        Ok(Self {
            store: Store::open(path)?,
        })
    }

    /// A store that lives in memory, for tests and previews.
    pub fn in_memory() -> Result<Self, LibraryError> {
        Ok(Self {
            store: Store::in_memory()?,
        })
    }

    /// The record for a publication, found by any identity component, or `None`.
    pub fn read(
        &self,
        identity: &PublicationIdentity,
    ) -> Result<Option<ReadingProgress>, LibraryError> {
        Ok(self.store.progress(identity)?)
    }

    /// Records a position. Finished stays finished, and identity components fill in.
    pub fn write(&self, progress: &ReadingProgress) -> Result<(), LibraryError> {
        Ok(self.store.save_progress(progress)?)
    }

    /// Every record, most recently read first, at most `limit`.
    pub fn recent(&self, limit: usize) -> Result<Vec<ReadingProgress>, LibraryError> {
        Ok(self.store.recent_progress(limit)?)
    }

    /// The store underneath, for the calls this facade does not wrap.
    pub fn store(&self) -> &Store {
        &self.store
    }
}
