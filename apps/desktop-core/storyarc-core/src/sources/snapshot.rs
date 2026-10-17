//! What a folder held the last time it was looked at. Mirrored from `FolderSnapshot.swift`,
//! and identical on Android.
//!
//! `local-library` requires the app to "detect changes to a folder library without a full
//! rescan", and to reconcile "by comparing file modification times and sizes rather than
//! re-reading every archive". A walk that reads only directory entries is cheap; comparing
//! one against the last says exactly which files have to be opened.

use std::collections::HashMap;

use crate::domain::Timestamp;

/// One publication, as a directory listing describes it. The modification date and the
/// size together, because either alone misses a real case.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Entry {
    pub path: String,
    pub modified: Timestamp,
    pub size: i64,
}

/// What has to be done to catch up with a fresh walk.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Change {
    pub added: Vec<Entry>,
    pub changed: Vec<Entry>,
    /// Paths that have gone. Their rows go with them.
    pub removed: Vec<String>,
}

impl Change {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.changed.is_empty() && self.removed.is_empty()
    }

    /// The only files that have to be opened, which is the whole point of comparing.
    pub fn to_index(&self) -> Vec<Entry> {
        self.added.iter().chain(&self.changed).cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct FolderSnapshot {
    entries: HashMap<String, Entry>,
}

impl FolderSnapshot {
    pub fn new(entries: Vec<Entry>) -> Self {
        let mut map = HashMap::with_capacity(entries.len());
        for entry in entries {
            map.entry(entry.path.clone()).or_insert(entry);
        }
        Self { entries: map }
    }

    pub fn entries(&self) -> &HashMap<String, Entry> {
        &self.entries
    }

    /// What changed since this snapshot, or `None` when the walk cannot be believed: a walk
    /// that found nothing at all where something used to be is a stale permission or a
    /// provider that has not mounted, and reading it as "the reader deleted every book"
    /// empties their library.
    pub fn change(&self, walked: &[Entry]) -> Option<Change> {
        if walked.is_empty() && !self.entries.is_empty() {
            return None;
        }
        let mut change = Change::default();
        let mut seen = std::collections::HashSet::with_capacity(walked.len());
        for entry in walked {
            seen.insert(entry.path.as_str());
            match self.entries.get(&entry.path) {
                None => change.added.push(entry.clone()),
                Some(known) if known != entry => change.changed.push(entry.clone()),
                Some(_) => {}
            }
        }
        // Sorted, so a reconcile does the same thing twice given the same folder.
        change.removed = self
            .entries
            .keys()
            .filter(|path| !seen.contains(path.as_str()))
            .cloned()
            .collect();
        change.removed.sort();
        Some(change)
    }

    /// The snapshot a walk leaves behind: the same guard as `change`, so an empty walk over
    /// a full folder leaves the only record of what it held alone.
    pub fn updated(&self, walked: Vec<Entry>) -> Self {
        if walked.is_empty() && !self.entries.is_empty() {
            self.clone()
        } else {
            Self::new(walked)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(path: &str, modified: i64, size: i64) -> Entry {
        Entry {
            path: path.into(),
            modified: Timestamp(modified),
            size,
        }
    }

    #[test]
    fn a_fresh_walk_reports_arrivals_changes_and_departures() {
        let before = FolderSnapshot::new(vec![
            entry("/a", 1, 10),
            entry("/b", 1, 10),
            entry("/c", 1, 10),
        ]);
        let change = before
            .change(&[entry("/a", 1, 10), entry("/b", 2, 10), entry("/d", 1, 5)])
            .unwrap();
        assert_eq!(change.added, [entry("/d", 1, 5)]);
        assert_eq!(change.changed, [entry("/b", 2, 10)]);
        assert_eq!(change.removed, ["/c"]);
        assert_eq!(change.to_index().len(), 2);
        assert!(
            before
                .change(&[entry("/a", 1, 10), entry("/b", 1, 10), entry("/c", 1, 10)])
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn an_empty_walk_over_a_full_folder_is_refused_and_leaves_the_snapshot_alone() {
        let before = FolderSnapshot::new(vec![entry("/a", 1, 10)]);
        assert_eq!(before.change(&[]), None);
        assert_eq!(before.updated(vec![]), before);
        assert!(FolderSnapshot::default().change(&[]).unwrap().is_empty());
        assert_eq!(before.updated(vec![entry("/z", 1, 1)]).entries().len(), 1);
    }
}
