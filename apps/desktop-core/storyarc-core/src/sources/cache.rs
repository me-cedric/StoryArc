//! The metadata cache: what each network source listed when it last answered, so the library
//! stays browsable with the source away (`offline-downloads`, *Reading fully offline*: "the
//! cached metadata [is] available with no degradation"), and so a refresh can be compared
//! with what came before.
//!
//! One JSON file per source, named by a digest of its id, written beside itself and renamed
//! into place. The cache lives in the cache folder ([`crate::paths`]), never a roaming one,
//! and each source's entry clears on its own (*Storage on a desktop*).

use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::domain::Timestamp;

/// One source's cached listing and when it was fetched.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Cached<T> {
    pub fetched_at: Timestamp,
    pub value: T,
}

#[derive(Debug, Clone)]
pub struct MetadataCache {
    root: PathBuf,
}

impl MetadataCache {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn file(&self, source_id: &str) -> PathBuf {
        let digest = Sha256::digest(source_id.as_bytes());
        let name: String = digest[..12].iter().map(|b| format!("{b:02x}")).collect();
        self.root.join(format!("{name}.json"))
    }

    /// Writes what a source listed now. A full disk is the caller's to name, in grey; the
    /// previous entry stays whole.
    pub fn write<T: Serialize>(
        &self,
        source_id: &str,
        value: &T,
        now: Timestamp,
    ) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.root)?;
        let bytes = serde_json::to_vec(&Cached {
            fetched_at: now,
            value,
        })
        .map_err(std::io::Error::other)?;
        let file = self.file(source_id);
        let mut staging = file.as_os_str().to_owned();
        staging.push(".saving");
        std::fs::write(&staging, bytes)?;
        std::fs::rename(&staging, &file)
    }

    /// What a source listed when it last answered, or `None` for nothing or a damaged entry.
    pub fn read<T: DeserializeOwned>(&self, source_id: &str) -> Option<Cached<T>> {
        let bytes = std::fs::read(self.file(source_id)).ok()?;
        serde_json::from_slice(&bytes).ok()
    }

    pub fn clear(&self, source_id: &str) {
        let _ = std::fs::remove_file(self.file(source_id));
    }

    pub fn clear_all(&self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }

    /// What the cache weighs, for the storage view.
    pub fn bytes(&self) -> u64 {
        size(&self.root)
    }
}

fn size(dir: &Path) -> u64 {
    std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .flatten()
                .filter_map(|e| e.metadata().ok())
                .filter(|m| m.is_file())
                .map(|m| m.len())
                .sum()
        })
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_listing_comes_back_after_the_source_goes_and_each_source_clears_alone() {
        let dir = tempfile::tempdir().unwrap();
        let cache = MetadataCache::new(dir.path().join("metadata"));
        assert!(cache.read::<Vec<String>>("a").is_none());
        cache
            .write("a", &vec!["one".to_owned(), "two".to_owned()], Timestamp(5))
            .unwrap();
        cache
            .write("b", &vec!["three".to_owned()], Timestamp(6))
            .unwrap();
        let back: Cached<Vec<String>> = cache.read("a").unwrap();
        assert_eq!(back.value, ["one", "two"]);
        assert_eq!(back.fetched_at, Timestamp(5));
        assert!(cache.bytes() > 0);
        cache.clear("a");
        assert!(cache.read::<Vec<String>>("a").is_none());
        assert!(cache.read::<Vec<String>>("b").is_some());
        cache.clear_all();
        assert_eq!(cache.bytes(), 0);
    }
}
