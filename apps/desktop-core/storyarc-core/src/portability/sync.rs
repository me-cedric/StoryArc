//! The sync document (`library-sync`), mirrored from StoryArcKit's `LibrarySync`.
//!
//! One file in a place the reader configured: a folder they picked (which may be a cloud
//! drive's folder; the app holds no account with it) or a share they added. A write is
//! read-merge-write against the file as it is at that moment, and replaces only the version
//! it read; a device that loses the race reads again and merges again, so neither device
//! drops what the other wrote. A provider's conflicted copy beside the file is merged and
//! removed. An unreachable place is grey: the caller keeps reading and syncs later.

use std::path::PathBuf;

use super::coder::{self, DocumentFailure};
use super::merge::{LibrarySnapshot, Merged, merging};
use crate::domain::Timestamp;

/// One file as the place holds it, and the version a write must still find to replace it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncFile {
    pub data: Vec<u8>,
    pub version: String,
}

/// The place could not be reached: grey, never red.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unreachable(pub String);

/// Where the document lives.
pub trait SyncPlace {
    fn names(&self) -> Result<Vec<String>, Unreachable>;
    fn read(&self, name: &str) -> Result<Option<SyncFile>, Unreachable>;
    /// Writes `data` only when the file is still at `replacing` (`None`: still absent).
    /// `Ok(false)` when another device wrote first.
    fn write(&self, name: &str, data: &[u8], replacing: Option<&str>) -> Result<bool, Unreachable>;
    fn delete(&self, name: &str) -> Result<bool, Unreachable>;
}

/// A folder on this system, or a provider's folder mounted as one.
#[derive(Debug, Clone)]
pub struct FolderPlace {
    root: PathBuf,
}

impl FolderPlace {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn version(data: &[u8]) -> String {
        use sha2::{Digest, Sha256};
        Sha256::digest(data)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }
}

fn away(error: std::io::Error) -> Unreachable {
    Unreachable(error.to_string())
}

impl SyncPlace for FolderPlace {
    fn names(&self) -> Result<Vec<String>, Unreachable> {
        let entries = std::fs::read_dir(&self.root).map_err(away)?;
        Ok(entries
            .flatten()
            .filter_map(|e| e.file_name().into_string().ok())
            .collect())
    }

    fn read(&self, name: &str) -> Result<Option<SyncFile>, Unreachable> {
        if !self.root.is_dir() {
            return Err(Unreachable(format!("{} is not there", self.root.display())));
        }
        match std::fs::read(self.root.join(name)) {
            Ok(data) => Ok(Some(SyncFile {
                version: Self::version(&data),
                data,
            })),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(away(e)),
        }
    }

    fn write(&self, name: &str, data: &[u8], replacing: Option<&str>) -> Result<bool, Unreachable> {
        let now = self.read(name)?.map(|f| f.version);
        if now.as_deref() != replacing {
            return Ok(false);
        }
        let staging = self.root.join(format!(".{name}.writing"));
        std::fs::write(&staging, data).map_err(away)?;
        std::fs::rename(&staging, self.root.join(name)).map_err(away)?;
        Ok(true)
    }

    fn delete(&self, name: &str) -> Result<bool, Unreachable> {
        Ok(std::fs::remove_file(self.root.join(name)).is_ok())
    }
}

/// How a sync ended.
#[derive(Debug, Clone, PartialEq)]
pub enum SyncOutcome {
    Synced {
        merged: Box<Merged>,
        /// The conflicted copies merged in and removed.
        copies: Vec<String>,
    },
    /// The document there is one this app will not read; nothing was written.
    Refused(DocumentFailure),
    /// Every attempt lost the race to another device.
    Busy,
}

pub struct LibrarySync<P: SyncPlace> {
    pub place: P,
    pub device: String,
    pub app_version: String,
    pub file_name: String,
    pub attempts: usize,
}

impl<P: SyncPlace> LibrarySync<P> {
    pub const FILE_NAME: &'static str = "StoryArc Library.json";

    pub fn new(place: P, device: impl Into<String>, app_version: impl Into<String>) -> Self {
        Self {
            place,
            device: device.into(),
            app_version: app_version.into(),
            file_name: Self::FILE_NAME.into(),
            attempts: 3,
        }
    }

    /// Reads, merges this device in, and writes back, at `now`.
    pub fn sync(
        &self,
        local: &LibrarySnapshot,
        now: Timestamp,
    ) -> Result<SyncOutcome, Unreachable> {
        for _ in 0..self.attempts {
            let file = self.place.read(&self.file_name)?;
            let mut incoming = Vec::new();
            if let Some(file) = &file {
                match coder::decode(&file.data) {
                    Ok(document) => incoming.push(document),
                    Err(failure) => return Ok(SyncOutcome::Refused(failure)),
                }
            }
            let mut copies = Vec::new();
            let mut names: Vec<String> = self
                .place
                .names()?
                .into_iter()
                .filter(|n| is_conflicted_copy(n, &self.file_name))
                .collect();
            names.sort();
            for name in names {
                // A copy this app cannot read is left where it is.
                if let Some(copy) = self.place.read(&name)?
                    && let Ok(document) = coder::decode(&copy.data)
                {
                    incoming.push(document);
                    copies.push(name);
                }
            }
            let mut merged = Merged {
                snapshot: local.clone(),
                ..Merged::default()
            };
            for document in &incoming {
                let next = merging(document, &merged.snapshot, &self.device);
                merged.conflicts.extend(next.conflicts);
                merged.pins_added.extend(next.pins_added);
                merged.members_added += next.members_added;
                merged.sources_needing_sign_in = next.sources_needing_sign_in;
                merged.snapshot = next.snapshot;
            }
            let written = merged
                .snapshot
                .document(&self.app_version, now, &self.device, true);
            let bytes = coder::encode(&written);
            let replacing = file.as_ref().map(|f| f.version.as_str());
            if !self.place.write(&self.file_name, &bytes, replacing)? {
                continue;
            }
            for name in &copies {
                self.place.delete(name)?;
            }
            return Ok(SyncOutcome::Synced {
                merged: Box::new(merged),
                copies,
            });
        }
        Ok(SyncOutcome::Busy)
    }
}

/// Whether `name` is a provider's conflicted copy of `original`: `Name 2.json`,
/// `Name (conflict).json` or `Name-suffix.json`.
pub fn is_conflicted_copy(name: &str, original: &str) -> bool {
    let (base, extension) = match original.rfind('.') {
        Some(dot) => (&original[..dot], &original[dot..]),
        None => (original, ""),
    };
    if name == original
        || !name.starts_with(base)
        || !name.ends_with(extension)
        || name.len() <= base.len() + extension.len()
    {
        return false;
    }
    let suffix = &name[base.len()..name.len() - extension.len()];
    let trimmed = suffix.trim_start();
    if trimmed.len() < suffix.len()
        && !trimmed.is_empty()
        && trimmed.chars().all(|c| c.is_ascii_digit())
    {
        return true;
    }
    if trimmed.starts_with('(') && trimmed.ends_with(')') && trimmed.len() > 2 {
        return true;
    }
    suffix.starts_with('-') && suffix.len() > 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_providers_conflicted_copies_are_recognised_and_nothing_else_is() {
        let original = "StoryArc Library.json";
        for copy in [
            "StoryArc Library 2.json",
            "StoryArc Library (Pixel's conflicted copy).json",
            "StoryArc Library-laptop.json",
        ] {
            assert!(is_conflicted_copy(copy, original), "{copy}");
        }
        for other in [
            "StoryArc Library.json",
            "StoryArc Library.txt",
            "StoryArc Library2.json",
            "Other.json",
            "StoryArc Library ().json",
        ] {
            assert!(!is_conflicted_copy(other, original), "{other}");
        }
    }
}
