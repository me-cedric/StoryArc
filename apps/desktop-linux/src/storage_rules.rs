//! Storage on a desktop (task 3.19; `desktop-experience`, *Storage on a desktop*): what the
//! app uses, each store clearable on its own, and a full disk named in grey. Pure over
//! folders, so each rule is a test on a scratch directory.

use std::io;
use std::path::{Path, PathBuf};

use storyarc_core::paths::StorageLocations;

use crate::strings::tr;

/// One store the preferences list.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Store {
    Downloads,
    Covers,
    Records,
}

impl Store {
    pub const ALL: [Self; 3] = [Self::Downloads, Self::Covers, Self::Records];

    pub fn label(self) -> String {
        match self {
            Self::Downloads => tr("storage.downloads", "Downloads"),
            Self::Covers => tr("downloads.cache", "Cover cache"),
            Self::Records => tr("storage.records", "Library records"),
        }
    }

    /// Whether the reader can empty the store without losing what they made: downloads
    /// come down again and covers are rebuilt, but the records hold the reading positions.
    pub fn clearable_by_a_tap(self) -> bool {
        !matches!(self, Self::Records)
    }
}

/// Where each store lives, from the core's per-user locations.
pub fn folder(locations: &StorageLocations, store: Store) -> PathBuf {
    match store {
        Store::Downloads => locations.downloads.clone(),
        Store::Covers => locations.cache.clone(),
        Store::Records => locations.data.clone(),
    }
}

/// The bytes under a folder, files only, symbolic links not followed. A missing folder
/// holds nothing.
pub fn size_of(folder: &Path) -> u64 {
    let Ok(entries) = std::fs::read_dir(folder) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| match entry.file_type() {
            Ok(kind) if kind.is_dir() => size_of(&entry.path()),
            Ok(kind) if kind.is_file() => entry.metadata().map_or(0, |m| m.len()),
            _ => 0,
        })
        .sum()
}

/// Empties a folder and leaves the folder. The files of the library's records are never
/// touched by this: `Store::Records` is cleared through the store's own calls.
pub fn clear(folder: &Path) -> io::Result<()> {
    if !folder.exists() {
        return Ok(());
    }
    for entry in std::fs::read_dir(folder)? {
        let path = entry?.path();
        if path.is_dir() && !path.is_symlink() {
            std::fs::remove_dir_all(&path)?;
        } else {
            std::fs::remove_file(&path)?;
        }
    }
    Ok(())
}

/// Whether a write failed because the disk is full (ENOSPC on Linux, 28).
pub fn is_disk_full(error: &io::Error) -> bool {
    error.raw_os_error() == Some(28) || error.kind() == io::ErrorKind::StorageFull
}

/// The grey line for a full disk: named, what was kept, and the offer.
pub fn full_disk_line() -> String {
    tr(
        "storage.diskFull",
        "The disk is full. StoryArc kept what it had. Clearing the cover cache or a download frees space.",
    )
}

/// The line for any other failed write, when there is one to say.
pub fn failed_write_line(error: &io::Error) -> String {
    if is_disk_full(error) {
        full_disk_line()
    } else {
        tr("storage.writeFailed", "StoryArc could not save that.")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scratch::Scratch;
    use storyarc_core::paths::{Platform, Sandbox};

    fn locations() -> StorageLocations {
        StorageLocations::resolve(
            Platform::Linux,
            |name| match name {
                "XDG_DATA_HOME" => Some("/home/ada/.local/share".into()),
                "XDG_CACHE_HOME" => Some("/home/ada/.cache".into()),
                "HOME" => Some("/home/ada".into()),
                _ => None,
            },
            Sandbox::None,
        )
    }

    #[test]
    fn each_store_has_its_own_folder_and_none_is_roaming() {
        let at = locations();
        let folders: Vec<_> = Store::ALL.iter().map(|s| folder(&at, *s)).collect();
        assert_eq!(folders.len(), 3);
        assert!(folders[0] != folders[1] && folders[1] != folders[2]);
        assert!(folders.iter().all(|f| !StorageLocations::is_roaming(f)));
    }

    #[test]
    fn the_size_counts_every_file_under_a_folder_and_a_missing_folder_is_empty() {
        let dir = Scratch::new("size");
        std::fs::create_dir_all(dir.join("a/b")).unwrap();
        std::fs::write(dir.join("one"), [0u8; 10]).unwrap();
        std::fs::write(dir.join("a/b/two"), [0u8; 32]).unwrap();
        assert_eq!(size_of(dir.path()), 42);
        assert_eq!(size_of(&dir.join("nowhere")), 0);
    }

    #[test]
    fn clearing_one_store_empties_it_and_touches_no_other() {
        let dir = Scratch::new("clear");
        let covers = dir.join("covers");
        let downloads = dir.join("downloads");
        std::fs::create_dir_all(covers.join("sub")).unwrap();
        std::fs::create_dir_all(&downloads).unwrap();
        std::fs::write(covers.join("sub/c.png"), [1u8; 8]).unwrap();
        std::fs::write(downloads.join("book.cbz"), [2u8; 8]).unwrap();
        clear(&covers).unwrap();
        assert!(covers.is_dir());
        assert_eq!(size_of(&covers), 0);
        assert_eq!(size_of(&downloads), 8);
        assert!(clear(&dir.join("never-made")).is_ok());
    }

    #[test]
    fn the_records_are_not_a_one_tap_clear() {
        assert!(Store::Downloads.clearable_by_a_tap());
        assert!(Store::Covers.clearable_by_a_tap());
        assert!(!Store::Records.clearable_by_a_tap());
    }

    #[test]
    fn a_full_disk_is_named_and_another_failure_is_not_called_one() {
        let full = io::Error::from_raw_os_error(28);
        assert!(is_disk_full(&full));
        assert_eq!(failed_write_line(&full), full_disk_line());
        let denied = io::Error::from(io::ErrorKind::PermissionDenied);
        assert!(!is_disk_full(&denied));
        assert_ne!(failed_write_line(&denied), full_disk_line());
        assert!(full_disk_line().contains("kept what it had"));
    }
}
