//! A directory of ordered images, read as one publication. Mirrored from
//! `ImageFolderArchive.swift`.
//!
//! `publication-formats` lists a plain folder alongside the archive formats, and it behaves
//! like one: the same page filter, the same natural sort, the same `ComicInfo.xml`
//! handling. Subdirectories are walked, because chapters-as-folders is how unpacked comics
//! are laid out, and ordering by full path makes `ch10` follow `ch2` as it does in a CBZ.

use std::path::{Path, PathBuf};

use super::comic_archive::ComicArchiveError;
use super::comic_info::ComicInfo;
use super::page_ordering::{CoverSelection, PageDeclarations, PageEntry, PageOrdering};

pub struct ImageFolderArchive {
    pub pages: Vec<PageEntry>,
    pub skipped_page_count: usize,
    pub comic_info: Option<ComicInfo>,
    root: PathBuf,
}

impl ImageFolderArchive {
    /// Walks the folder once, reading nothing but the directory entries and `ComicInfo.xml`.
    pub fn open(directory: impl AsRef<Path>) -> Result<Self, ComicArchiveError> {
        let root = directory.as_ref();
        if !root.is_dir() {
            return Err(ComicArchiveError::UnrecognisedContainer);
        }
        let mut candidates = Vec::new();
        let mut skipped = 0;
        let mut comic_info = None;
        let mut pending = vec![root.to_path_buf()];
        while let Some(directory) = pending.pop() {
            let Ok(entries) = std::fs::read_dir(&directory) else {
                continue;
            };
            for entry in entries.flatten() {
                let path = entry.path();
                // Symbolic links are not followed. A publication folder is chosen by the
                // user, but it is still untrusted input: a link pointing outside the root
                // would let a crafted folder read arbitrary files.
                let Ok(metadata) = std::fs::symlink_metadata(&path) else {
                    continue;
                };
                if metadata.file_type().is_symlink() {
                    continue;
                }
                if metadata.is_dir() {
                    pending.push(path);
                    continue;
                }
                let relative = relative_path(&path, root);
                if relative.to_lowercase().ends_with("comicinfo.xml") {
                    comic_info = std::fs::read(&path)
                        .ok()
                        .and_then(|data| ComicInfo::parse(&data));
                    continue;
                }
                if !PageOrdering::is_page(&relative) {
                    continue;
                }
                // A zero-length file is a page that will never decode. Counting it as
                // skipped is what lets the reader say "opened 10, skipped 2".
                if metadata.len() == 0 {
                    skipped += 1;
                    continue;
                }
                candidates.push(PageEntry::new(relative, Some(metadata.len())));
            }
        }
        Ok(Self {
            pages: PageOrdering::sorted(candidates),
            skipped_page_count: skipped,
            comic_info,
            root: root.to_path_buf(),
        })
    }

    pub fn cover_page(&self) -> Option<&PageEntry> {
        CoverSelection::cover(
            &self.pages,
            self.comic_info
                .as_ref()
                .and_then(|info| info.cover_page_index),
        )
    }

    pub fn double_page_indices(&self) -> Vec<usize> {
        let declared = self
            .comic_info
            .as_ref()
            .map(|info| info.double_page_indices.as_slice())
            .unwrap_or_default();
        PageDeclarations::spreads(&self.pages, declared)
    }

    /// One page's bytes. The path is re-checked against the root at read time rather than
    /// trusted from the walk, because the filesystem can change between the two.
    pub fn data(&self, page: &PageEntry) -> Result<Vec<u8>, ComicArchiveError> {
        if page
            .path
            .split('/')
            .any(|component| component == ".." || component.is_empty())
        {
            return Err(ComicArchiveError::Unreadable);
        }
        let path = self.root.join(&page.path);
        std::fs::read(path).map_err(|_| ComicArchiveError::Unreadable)
    }

    /// The bytes the pages add up to, which is what a folder weighs.
    pub fn byte_count(&self) -> i64 {
        self.pages
            .iter()
            .map(|page| page.byte_count.unwrap_or(0) as i64)
            .sum()
    }
}

/// The entry's path under the root, with `/` as the separator whatever the platform uses,
/// so page order and `ComicInfo` page indices agree with the same folder packed as a CBZ.
fn relative_path(path: &Path, root: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    const PNG: &[u8] = &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1];

    #[test]
    fn pages_are_found_under_chapters_in_natural_order_and_junk_is_excluded() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("ch10")).unwrap();
        std::fs::create_dir_all(root.join("ch2")).unwrap();
        std::fs::write(root.join("ch10/p1.png"), PNG).unwrap();
        std::fs::write(root.join("ch2/p2.png"), PNG).unwrap();
        std::fs::write(root.join("ch2/p1.png"), PNG).unwrap();
        std::fs::write(root.join("ch2/empty.png"), b"").unwrap();
        std::fs::write(root.join("Thumbs.db"), b"x").unwrap();
        std::fs::write(
            root.join("ComicInfo.xml"),
            b"<ComicInfo><Series>S</Series></ComicInfo>",
        )
        .unwrap();

        let archive = ImageFolderArchive::open(root).unwrap();
        let paths: Vec<&str> = archive.pages.iter().map(|p| p.path.as_str()).collect();
        assert_eq!(paths, ["ch2/p1.png", "ch2/p2.png", "ch10/p1.png"]);
        assert_eq!(archive.skipped_page_count, 1);
        assert_eq!(
            archive.comic_info.as_ref().unwrap().series.as_deref(),
            Some("S")
        );
        assert_eq!(archive.cover_page().unwrap().path, "ch2/p1.png");
        assert_eq!(archive.data(&archive.pages[0]).unwrap(), PNG);
        assert_eq!(archive.byte_count(), 3 * PNG.len() as i64);
        assert!(
            archive
                .data(&PageEntry::new("../etc/passwd", None))
                .is_err()
        );
    }

    #[test]
    fn a_file_is_not_a_folder() {
        let file = tempfile::NamedTempFile::new().unwrap();
        assert!(matches!(
            ImageFolderArchive::open(file.path()),
            Err(ComicArchiveError::UnrecognisedContainer)
        ));
    }
}
