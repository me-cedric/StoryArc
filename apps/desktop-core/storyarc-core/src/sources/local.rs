//! A local folder as a source: the walk that turns it into publications, and the cheap
//! listing a returning app reconciles against (task 2.2 of `desktop-clients`). Mirrored
//! from `LibraryScanner.swift` and `LibraryScanner+Listing.swift`.
//!
//! `local-library`: a scan "walks it recursively, identifies supported publications,
//! extracts covers and metadata, and reports progress as a count of items found", and a
//! returning app "reconciles by comparing file modification times and sizes rather than
//! re-reading every archive".

use std::path::{Path, PathBuf};

use super::index::{AUDIO_EXTENSIONS, IndexError, PublicationIndexer, file_name, normalized_path};
use super::snapshot::Entry;
use crate::domain::{NaturalOrder, Publication, Timestamp};
use crate::io::CancelToken;

/// How many directories the native watchers of task 2.3 cover at once, breadth-first from
/// each watched root: the phones' ninety-six (`FolderWatcher.limit` on iOS). Recorded here,
/// beside the walk that counts them, because a library of ten thousand comics in a thousand
/// series would spend every descriptor a process has; past it a folder is rescanned rather
/// than watched live, and the app says so once, in grey (`desktop-experience`, *Live folder
/// watching*).
pub const WATCH_DIRECTORY_LIMIT: usize = 96;

/// Extensions worth opening. A cheap pre-filter, not the decision — format is still
/// determined from content, so a `.cbz` that is really a RAR opens as a RAR.
pub const CANDIDATE_EXTENSIONS: [&str; 8] =
    ["cbz", "cbr", "cb7", "cbt", "epub", "pdf", "zip", "rar"];

/// Audio containers worth opening only so that they can be refused by name.
const PROTECTED_AUDIO_EXTENSIONS: [&str; 2] = ["aax", "aaxc"];

/// Why a scan passed a file over, as a case the apps word.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkipReason {
    /// A container StoryArc recognises and does not read, named. The name is content.
    UnsupportedFormat(String),
    NotThere,
    FormatNotRecognised,
    ArchivePasswordProtected,
    ArchiveUnreadable,
    ContentProtected,
    /// A failure the indexer wrote no case for.
    Unknown,
}

impl From<IndexError> for SkipReason {
    fn from(error: IndexError) -> Self {
        match error {
            IndexError::Unsupported(format) => Self::UnsupportedFormat(format),
            IndexError::NotThere => Self::NotThere,
            IndexError::FormatNotRecognised => Self::FormatNotRecognised,
            IndexError::ArchivePasswordProtected => Self::ArchivePasswordProtected,
            IndexError::ArchiveUnreadable => Self::ArchiveUnreadable,
            IndexError::ContentProtected => Self::ContentProtected,
            IndexError::Cancelled => Self::Unknown,
        }
    }
}

/// A file the walk recognised and did not index.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkippedFile {
    pub path: String,
    pub reason: SkipReason,
}

/// What a walk produced.
#[derive(Debug, Clone, Default)]
pub struct ScanReport {
    /// In walk order: depth-first, natural order within a directory, so the order a
    /// reader sees matches the order a file browser shows.
    pub publications: Vec<Publication>,
    pub skipped: Vec<SkippedFile>,
    /// Directories the walk could not list. The difference between a folder that is empty
    /// and one the app may no longer read; a caller that ignores it tells a reader whose
    /// folder access lapsed that their library is empty.
    pub unreadable_folders: Vec<String>,
    /// Containers opened. Zero on a second scan of an unchanged folder is the reconcile
    /// working.
    pub opened: usize,
    /// Publications handed back from `known` without opening their container.
    pub reused: usize,
    pub was_cancelled: bool,
}

/// A folder to scan.
pub struct FolderScan {
    root: PathBuf,
}

impl FolderScan {
    pub fn new(root: impl AsRef<Path>) -> Self {
        Self {
            root: root.as_ref().to_path_buf(),
        }
    }

    /// Walks the folder and indexes what it finds. Costs one directory listing per folder
    /// and one container open per publication `known` does not vouch for.
    ///
    /// `known` answers what the library already holds for a path: a publication handed
    /// back whose size and modification date still match the file is emitted as it is,
    /// and the container is never opened. The token stops the walk between files.
    pub fn scan(
        &self,
        known: impl Fn(&Path) -> Option<Publication>,
        cancel: &CancelToken,
    ) -> ScanReport {
        let mut report = ScanReport::default();
        // The picked folder's own name is not a series: it is the library.
        self.walk(&self.root, None, &known, cancel, &mut report);
        report
    }

    /// What the folder holds, without opening anything in it: one row per publication,
    /// with the size and date a reconcile compares. The same decisions as `scan`, because
    /// the two lists are compared against each other.
    pub fn entries(&self) -> Vec<Entry> {
        let mut found = Vec::new();
        self.list(&self.root, &mut found);
        found
    }

    fn walk(
        &self,
        directory: &Path,
        series_hint: Option<&str>,
        known: &impl Fn(&Path) -> Option<Publication>,
        cancel: &CancelToken,
        report: &mut ScanReport,
    ) {
        if cancel.is_cancelled() {
            report.was_cancelled = true;
            return;
        }
        let Some(listing) = Listing::of(directory) else {
            report.unreadable_folders.push(normalized_path(directory));
            return;
        };
        // A directory holding images and no publications is itself one publication. A
        // directory holding publications is a shelf.
        if listing.is_one_publication() {
            Self::index(directory, series_hint, known, report);
            return;
        }
        for file in listing
            .publications
            .iter()
            .chain(&listing.audio)
            .chain(&listing.locked)
        {
            if cancel.is_cancelled() {
                report.was_cancelled = true;
                return;
            }
            Self::index(file, series_hint, known, report);
        }
        for child in &listing.directories {
            self.walk(child, Some(&file_name(child)), known, cancel, report);
        }
    }

    fn index(
        path: &Path,
        series_hint: Option<&str>,
        known: &impl Fn(&Path) -> Option<Publication>,
        report: &mut ScanReport,
    ) {
        // The reconcile `local-library` asks for. One `stat` decides whether the container
        // has to be opened at all.
        if let Some(cached) = known(Path::new(&normalized_path(path))) {
            let facts = std::fs::metadata(path).ok();
            // A folder of images has no size of its own, so it is compared on its
            // modification date alone, as the listing compares it: the size the record
            // carries is what its pages added up to, and it is taken as read.
            let size = facts.as_ref().map(|m| {
                if m.is_dir() {
                    cached.file_size.unwrap_or(0)
                } else {
                    m.len() as i64
                }
            });
            let moment = facts
                .as_ref()
                .and_then(|m| m.modified().ok())
                .map(Timestamp::from_system_time);
            if cached.matches_file(size, moment) {
                report.publications.push(cached);
                report.reused += 1;
                return;
            }
        }
        match PublicationIndexer::index_path(path, series_hint) {
            Ok(publication) => {
                report.opened += 1;
                report.publications.push(publication);
            }
            Err(error) => {
                // A refusal by name costs a sniff of the first bytes, not an open; only a
                // container that was read counts as one.
                if matches!(
                    error,
                    IndexError::ArchivePasswordProtected
                        | IndexError::ArchiveUnreadable
                        | IndexError::Cancelled
                ) {
                    report.opened += 1;
                }
                report.skipped.push(SkippedFile {
                    path: normalized_path(path),
                    reason: error.into(),
                });
            }
        }
    }

    fn list(&self, directory: &Path, found: &mut Vec<Entry>) {
        let Some(listing) = Listing::of(directory) else {
            return;
        };
        if listing.is_one_publication() {
            found.push(Self::entry(directory));
            return;
        }
        for file in listing
            .publications
            .iter()
            .chain(&listing.audio)
            .chain(&listing.locked)
        {
            found.push(Self::entry(file));
        }
        for child in &listing.directories {
            self.list(child, found);
        }
    }

    /// One listing row. A folder of images has no size of its own, so it is compared on
    /// its modification date alone.
    fn entry(path: &Path) -> Entry {
        let metadata = std::fs::metadata(path).ok();
        Entry {
            path: normalized_path(path),
            modified: metadata
                .as_ref()
                .and_then(|m| m.modified().ok())
                .map(Timestamp::from_system_time)
                .unwrap_or_default(),
            size: metadata
                .filter(|m| m.is_file())
                .map(|m| m.len() as i64)
                .unwrap_or(0),
        }
    }
}

/// What a directory holds, split and ordered the way the walk reads it.
struct Listing {
    publications: Vec<PathBuf>,
    images: usize,
    audio: Vec<PathBuf>,
    locked: Vec<PathBuf>,
    directories: Vec<PathBuf>,
}

impl Listing {
    /// `None` when the directory could not be listed at all — the one fact that separates
    /// a folder with nothing in it from a folder the app cannot read.
    fn of(directory: &Path) -> Option<Self> {
        let mut children: Vec<PathBuf> = std::fs::read_dir(directory)
            .ok()?
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| !file_name(path).starts_with('.'))
            .collect();
        // Natural order, case-insensitively, so the order matches a file browser's.
        children.sort_by(|a, b| NaturalOrder::compare(&file_name(a), &file_name(b)));

        let mut listing = Self {
            publications: Vec::new(),
            images: 0,
            audio: Vec::new(),
            locked: Vec::new(),
            directories: Vec::new(),
        };
        for child in children {
            // Symbolic links are not followed, for the reason the image folder gives.
            let Ok(metadata) = std::fs::symlink_metadata(&child) else {
                continue;
            };
            if metadata.file_type().is_symlink() {
                continue;
            }
            if metadata.is_dir() {
                listing.directories.push(child);
                continue;
            }
            let extension =
                crate::formats::PageOrdering::extension(&file_name(&child)).unwrap_or_default();
            if CANDIDATE_EXTENSIONS.contains(&extension.as_str()) {
                listing.publications.push(child);
            } else if crate::formats::PageOrdering::IMAGE_EXTENSIONS.contains(&extension.as_str()) {
                listing.images += 1;
            } else if AUDIO_EXTENSIONS.contains(&extension.as_str()) {
                listing.audio.push(child);
            } else if PROTECTED_AUDIO_EXTENSIONS.contains(&extension.as_str()) {
                listing.locked.push(child);
            }
        }
        Some(listing)
    }

    /// Whether this directory is one publication rather than a shelf: images and no packed
    /// publications, or audio parts with no subdirectories.
    fn is_one_publication(&self) -> bool {
        self.publications.is_empty()
            && (self.images > 0 || (!self.audio.is_empty() && self.directories.is_empty()))
    }
}
