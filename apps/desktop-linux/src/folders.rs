//! The folders the reader chose, as the app keeps them between runs, and what each one's
//! access looks like now (task 2.31). Pure; `sources.rs` is the GTK and core side.
//!
//! In the Flatpak, `GtkFileDialog` goes through the file chooser portal, which hands the
//! app a path under the document portal (`/run/user/<uid>/doc/…`). That path is the
//! stored grant: it reads again after a relaunch without a prompt, it passes no change
//! events (so the core polls it), and when the reader or the system withdraws it the path
//! stops reading (`desktop-experience`, Choosing folders and keeping access).

use std::path::{Path, PathBuf};

/// One chosen folder.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FolderRecord {
    pub path: PathBuf,
    /// Granted through the document portal rather than reached by its own path.
    pub portal_granted: bool,
}

impl FolderRecord {
    pub fn new(path: PathBuf) -> Self {
        let portal_granted = is_portal_path(&path);
        Self {
            path,
            portal_granted,
        }
    }

    /// The name the library shows for the folder.
    pub fn name(&self) -> String {
        self.path.file_name().map_or_else(
            || self.path.display().to_string(),
            |name| name.to_string_lossy().into_owned(),
        )
    }
}

/// Whether a path is one the document portal exported.
pub fn is_portal_path(path: &Path) -> bool {
    let text = path.to_string_lossy();
    text.starts_with("/run/flatpak/doc/")
        || (text.starts_with("/run/user/") && text.contains("/doc/"))
}

/// The sources file: one folder per line, its kind, a tab, its path.
pub fn save(records: &[FolderRecord]) -> String {
    records
        .iter()
        .map(|record| {
            let kind = if record.portal_granted {
                "portal"
            } else {
                "path"
            };
            format!("{kind}\t{}\n", record.path.display())
        })
        .collect()
}

/// Reads the sources file back. A damaged line is skipped and a folder listed twice is
/// kept once, so the library always opens.
pub fn restore(text: &str) -> Vec<FolderRecord> {
    let mut records: Vec<FolderRecord> = Vec::new();
    for line in text.lines() {
        let Some((kind, path)) = line.split_once('\t') else {
            continue;
        };
        if path.is_empty() || records.iter().any(|record| record.path == Path::new(path)) {
            continue;
        }
        let portal_granted = match kind {
            "portal" => true,
            "path" => false,
            _ => continue,
        };
        records.push(FolderRecord {
            path: PathBuf::from(path),
            portal_granted,
        });
    }
    records
}

/// Adds a folder unless it is there already. Returns whether it was added.
pub fn add(records: &mut Vec<FolderRecord>, path: PathBuf) -> bool {
    if records.iter().any(|record| record.path == path) {
        return false;
    }
    records.push(FolderRecord::new(path));
    true
}

/// Removes a folder library by its path. The files are untouched, and so are the reading
/// positions, which a folder added again finds. Returns whether it was there.
pub fn remove(records: &mut Vec<FolderRecord>, path: &Path) -> bool {
    let before = records.len();
    records.retain(|record| record.path != path);
    records.len() != before
}

/// Whether a folder can be read now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Access {
    Readable,
    /// The grant was withdrawn, or the system denies the folder: one action chooses it again.
    Withdrawn,
    /// Its volume is not connected: it returns by itself when the volume does.
    Offline,
}

impl Access {
    /// A portal path that no longer reads was revoked; a direct path that is not there is
    /// on a volume that is not mounted; a direct path that is there and will not list is
    /// denied.
    pub fn of(record: &FolderRecord, exists: bool, lists: bool) -> Self {
        if lists {
            Self::Readable
        } else if record.portal_granted || exists {
            Self::Withdrawn
        } else {
            Self::Offline
        }
    }

    /// The grey line under the folder's name, or nothing when it reads.
    pub fn note(self) -> Option<&'static str> {
        match self {
            Self::Readable => None,
            Self::Withdrawn => Some("Needs access"),
            Self::Offline => Some("Offline"),
        }
    }
}

/// The line a polled folder carries once, in grey.
pub fn not_live_note(seconds: u64) -> String {
    format!("Not watched live. Checked every {seconds} seconds")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_document_portal_path_is_a_portal_grant_and_a_home_path_is_not() {
        assert!(FolderRecord::new("/run/user/1000/doc/a1b2c3/Comics".into()).portal_granted);
        assert!(is_portal_path(Path::new("/run/flatpak/doc/a1b2c3/Comics")));
        assert!(!FolderRecord::new("/home/reader/Comics".into()).portal_granted);
        assert!(!is_portal_path(Path::new("/run/user/1000/gvfs/smb-share")));
    }

    #[test]
    fn the_sources_file_reads_back_what_it_wrote() {
        let records = vec![
            FolderRecord::new("/run/user/1000/doc/x/Comics".into()),
            FolderRecord::new("/media/disk/Manga".into()),
        ];
        assert_eq!(restore(&save(&records)), records);
        assert_eq!(
            FolderRecord::new("/media/disk/Manga".into()).name(),
            "Manga"
        );
    }

    #[test]
    fn a_damaged_or_repeated_line_is_skipped() {
        let text = "path\t/a\nnonsense\nother\t/b\npath\t/a\nportal\t\n";
        assert_eq!(restore(text), vec![FolderRecord::new("/a".into())]);
        assert!(restore("").is_empty());
    }

    #[test]
    fn a_folder_is_added_once() {
        let mut records = Vec::new();
        assert!(add(&mut records, "/Comics".into()));
        assert!(!add(&mut records, "/Comics".into()));
        assert_eq!(records.len(), 1);
    }

    #[test]
    fn a_removed_folder_leaves_the_list_and_the_others_keep_their_order() {
        let mut records = vec![
            FolderRecord::new("/a".into()),
            FolderRecord::new("/b".into()),
            FolderRecord::new("/c".into()),
        ];
        assert!(remove(&mut records, Path::new("/b")));
        assert!(!remove(&mut records, Path::new("/b")));
        assert_eq!(
            records,
            [
                FolderRecord::new("/a".into()),
                FolderRecord::new("/c".into())
            ]
        );
    }

    #[test]
    fn a_withdrawn_grant_needs_access_and_an_unmounted_volume_is_offline() {
        let portal = FolderRecord::new("/run/user/1000/doc/x/Comics".into());
        let direct = FolderRecord::new("/media/disk/Comics".into());
        assert_eq!(Access::of(&portal, true, true), Access::Readable);
        assert_eq!(Access::of(&portal, false, false), Access::Withdrawn);
        assert_eq!(Access::of(&direct, false, false), Access::Offline);
        assert_eq!(Access::of(&direct, true, false), Access::Withdrawn);
        assert_eq!(Access::Readable.note(), None);
        assert_eq!(Access::Withdrawn.note(), Some("Needs access"));
        assert_eq!(Access::Offline.note(), Some("Offline"));
    }

    #[test]
    fn a_polled_folder_names_its_interval() {
        assert_eq!(
            not_live_note(5),
            "Not watched live. Checked every 5 seconds"
        );
    }
}
