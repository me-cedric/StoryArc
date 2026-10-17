//! The offline edit queue for server-backed shelves, mirrored from StoryArcKit's
//! `ShelfEdit.swift` and `ShelfPull.swift` (`collections-and-reading-lists`, *Editing while
//! the server is unreachable* and *Conflicting edit*).
//!
//! An edit made while the server is away is applied locally, marked pending, written down,
//! and pushed on reconnection. On reconnection the server's answer is compared with what it
//! held when it last answered (the baseline):
//!
//! | Situation | Result |
//! | --- | --- |
//! | Nothing waiting | settle nothing, say nothing |
//! | The server already holds everything that was waiting | settled, silently |
//! | The server holds what it held when the edit was made | push what is outstanding |
//! | The server moved under an outstanding edit | server wins, edit discarded, tell once |
//! | This shelf has never answered this device | push: losing the edit is what offline must never do |

use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::domain::Timestamp;

/// Which of the two ideas a server shelf is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum ShelfKind {
    #[serde(rename = "collection")]
    Collection,
    #[serde(rename = "list")]
    ReadingList,
}

impl ShelfKind {
    pub fn token(self) -> &'static str {
        match self {
            Self::Collection => "collection",
            Self::ReadingList => "list",
        }
    }

    pub fn of_token(text: &str) -> Option<Self> {
        match text {
            "collection" => Some(Self::Collection),
            "list" => Some(Self::ReadingList),
            _ => None,
        }
    }
}

fn reading_list() -> ShelfKind {
    ShelfKind::ReadingList
}

/// A server, one of its shelves, and which kind: none of the three names a shelf alone,
/// because one Kavita server numbers its collections and its lists from one apiece.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShelfKey {
    #[serde(rename = "sourceID", alias = "sourceId")]
    pub source_id: String,
    #[serde(rename = "shelfID", alias = "shelfId")]
    pub shelf_id: i64,
    /// Absent in a key written before the kind existed, which was a reading list.
    #[serde(default = "reading_list")]
    pub kind: ShelfKind,
}

impl ShelfKey {
    pub fn new(source_id: impl Into<String>, shelf_id: i64, kind: ShelfKind) -> Self {
        Self {
            source_id: source_id.into(),
            shelf_id,
            kind,
        }
    }

    pub fn token(&self) -> String {
        format!("{}/{}:{}", self.source_id, self.kind.token(), self.shelf_id)
    }
}

/// One addition the server has not seen.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShelfEdit {
    pub shelf: ShelfKey,
    /// The entry, named the way the server names its own.
    pub entry: String,
    /// What the pending row says, since the server cannot be asked yet.
    pub title: String,
    pub made_at: Timestamp,
}

impl ShelfEdit {
    /// The same entry added to the same shelf twice is one pending edit.
    pub fn id(&self) -> String {
        format!("{}/{}", self.shelf.token(), self.entry)
    }
}

/// One row of a list as the reader sees it, pending or not.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShelfEntry {
    pub id: String,
    pub title: String,
    pub is_pending: bool,
}

/// What a shelf held the last time it answered.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShelfSnapshot {
    pub shelf: ShelfKey,
    pub entries: Vec<String>,
}

/// A conflict not yet told: "the user is told once what changed".
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShelfConflictNotice {
    pub id: String,
    pub shelf: ShelfKey,
    pub shelf_name: String,
    /// The titles dropped; empty for an order conflict.
    pub discarded: Vec<String>,
    pub at: Timestamp,
    #[serde(default)]
    pub is_order: bool,
}

impl ShelfConflictNotice {
    pub fn new(
        shelf: ShelfKey,
        shelf_name: impl Into<String>,
        discarded: Vec<String>,
        at: Timestamp,
    ) -> Self {
        Self {
            id: format!("{}/{}", shelf.token(), at.0),
            shelf,
            shelf_name: shelf_name.into(),
            discarded,
            at,
            is_order: false,
        }
    }
}

/// Everything owed to servers, everything last seen from them, and everything still to say.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShelfEditQueue {
    #[serde(default)]
    pub edits: Vec<ShelfEdit>,
    #[serde(default)]
    pub baselines: Vec<ShelfSnapshot>,
    #[serde(default)]
    pub notices: Vec<ShelfConflictNotice>,
}

impl ShelfEditQueue {
    /// Records an edit, replacing an earlier one for the same entry on the same shelf.
    pub fn queueing(&self, edit: ShelfEdit) -> Self {
        let id = edit.id();
        let mut next = self.clone();
        next.edits.retain(|e| e.id() != id);
        next.edits.push(edit);
        next
    }

    /// Forgets edits nothing more is owed for: delivered, or discarded by a conflict.
    pub fn dropping(&self, done: &[ShelfEdit]) -> Self {
        let gone: HashSet<String> = done.iter().map(ShelfEdit::id).collect();
        let mut next = self.clone();
        next.edits.retain(|e| !gone.contains(&e.id()));
        next
    }

    pub fn recording(&self, snapshot: ShelfSnapshot) -> Self {
        let mut next = self.clone();
        next.baselines.retain(|b| b.shelf != snapshot.shelf);
        next.baselines.push(snapshot);
        next
    }

    pub fn baseline(&self, shelf: &ShelfKey) -> Option<&[String]> {
        self.baselines
            .iter()
            .find(|b| &b.shelf == shelf)
            .map(|b| b.entries.as_slice())
    }

    /// The edits owed to one shelf, oldest first.
    pub fn pending(&self, shelf: &ShelfKey) -> Vec<ShelfEdit> {
        let mut edits: Vec<ShelfEdit> = self
            .edits
            .iter()
            .filter(|e| &e.shelf == shelf)
            .cloned()
            .collect();
        edits.sort_by_key(|e| e.made_at);
        edits
    }

    pub fn noting(&self, notice: ShelfConflictNotice) -> Self {
        let mut next = self.clone();
        next.notices.push(notice);
        next
    }

    /// Drops a notice that has been shown. This is the "once".
    pub fn acknowledging(&self, id: &str) -> Self {
        let mut next = self.clone();
        next.notices.retain(|n| n.id != id);
        next
    }

    pub fn next_notice(&self) -> Option<&ShelfConflictNotice> {
        self.notices.iter().min_by_key(|n| n.at)
    }

    /// Forgets everything a removed source defined.
    pub fn removing_all_from(&self, source_id: &str) -> Self {
        Self {
            edits: self
                .edits
                .iter()
                .filter(|e| e.shelf.source_id != source_id)
                .cloned()
                .collect(),
            baselines: self
                .baselines
                .iter()
                .filter(|b| b.shelf.source_id != source_id)
                .cloned()
                .collect(),
            notices: self
                .notices
                .iter()
                .filter(|n| n.shelf.source_id != source_id)
                .cloned()
                .collect(),
        }
    }
}

/// The outcome for one shelf.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShelfMergeOutcome {
    Push(Vec<ShelfEdit>),
    Settled(Vec<ShelfEdit>),
    Conflict {
        discarded: Vec<ShelfEdit>,
        settled: Vec<ShelfEdit>,
    },
}

/// The five rows of the table above.
pub fn merge(
    baseline: Option<&[String]>,
    remote: &[String],
    pending: &[ShelfEdit],
) -> ShelfMergeOutcome {
    let held: HashSet<&str> = remote.iter().map(String::as_str).collect();
    let (landed, waiting): (Vec<ShelfEdit>, Vec<ShelfEdit>) = pending
        .iter()
        .cloned()
        .partition(|e| held.contains(e.entry.as_str()));
    if waiting.is_empty() {
        return ShelfMergeOutcome::Settled(landed);
    }
    let Some(baseline) = baseline else {
        return ShelfMergeOutcome::Push(waiting);
    };
    // Our own arrivals out before comparing: a list that differs from the baseline only by
    // an edit this device made is a list nobody else touched.
    let ours: HashSet<&str> = landed.iter().map(|e| e.entry.as_str()).collect();
    let without_ours: Vec<&String> = remote
        .iter()
        .filter(|e| !ours.contains(e.as_str()))
        .collect();
    if without_ours.iter().copied().eq(baseline.iter()) {
        return ShelfMergeOutcome::Push(waiting);
    }
    ShelfMergeOutcome::Conflict {
        discarded: waiting,
        settled: landed,
    }
}

/// The list while edits wait: the server's entries in its order, then the outstanding ones,
/// oldest first, marked pending.
pub fn projecting(remote: &[ShelfEntry], pending: &[ShelfEdit]) -> Vec<ShelfEntry> {
    let held: HashSet<&str> = remote.iter().map(|e| e.id.as_str()).collect();
    let mut waiting: Vec<&ShelfEdit> = pending
        .iter()
        .filter(|e| !held.contains(e.entry.as_str()))
        .collect();
    waiting.sort_by_key(|e| e.made_at);
    remote
        .iter()
        .cloned()
        .chain(waiting.into_iter().map(|e| ShelfEntry {
            id: e.entry.clone(),
            title: e.title.clone(),
            is_pending: true,
        }))
        .collect()
}

/// One round of reconciling every shelf that answered.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ShelfPull {
    pub to_push: Vec<ShelfEdit>,
    pub to_drop: Vec<ShelfEdit>,
    pub conflicts: Vec<(ShelfKey, Vec<ShelfEdit>)>,
}

impl ShelfPull {
    /// A shelf that did not answer is absent from `remote` and left alone: the unreachable
    /// server is not a conflict.
    pub fn merging(remote: &[ShelfSnapshot], queue: &ShelfEditQueue) -> Self {
        let mut pull = Self::default();
        for snapshot in remote {
            let waiting = queue.pending(&snapshot.shelf);
            match merge(queue.baseline(&snapshot.shelf), &snapshot.entries, &waiting) {
                ShelfMergeOutcome::Push(outstanding) => pull.to_push.extend(outstanding),
                ShelfMergeOutcome::Settled(landed) => pull.to_drop.extend(landed),
                ShelfMergeOutcome::Conflict { discarded, settled } => {
                    pull.to_drop.extend(settled);
                    pull.to_drop.extend(discarded.iter().cloned());
                    pull.conflicts.push((snapshot.shelf.clone(), discarded));
                }
            }
        }
        pull
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shelf() -> ShelfKey {
        ShelfKey::new("server", 7, ShelfKind::ReadingList)
    }

    fn edit(entry: &str, at: i64) -> ShelfEdit {
        ShelfEdit {
            shelf: shelf(),
            entry: entry.into(),
            title: format!("Entry {entry}"),
            made_at: Timestamp(at),
        }
    }

    fn v(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn nothing_waiting_settles_nothing_and_says_nothing() {
        assert_eq!(
            merge(Some(&v(&["a"])), &v(&["a", "b"]), &[]),
            ShelfMergeOutcome::Settled(vec![])
        );
    }

    #[test]
    fn a_server_that_still_holds_what_it_held_takes_the_outstanding_edit() {
        let queued = edit("b", 1);
        assert_eq!(
            merge(Some(&v(&["a"])), &v(&["a"]), std::slice::from_ref(&queued)),
            ShelfMergeOutcome::Push(vec![queued])
        );
    }

    #[test]
    fn an_edit_the_server_already_has_is_settled_not_announced() {
        let queued = edit("b", 1);
        assert_eq!(
            merge(
                Some(&v(&["a"])),
                &v(&["a", "b"]),
                std::slice::from_ref(&queued)
            ),
            ShelfMergeOutcome::Settled(vec![queued])
        );
    }

    #[test]
    fn a_server_that_moved_under_an_outstanding_edit_wins() {
        let queued = edit("b", 1);
        assert_eq!(
            merge(
                Some(&v(&["a"])),
                &v(&["a", "c"]),
                std::slice::from_ref(&queued)
            ),
            ShelfMergeOutcome::Conflict {
                discarded: vec![queued],
                settled: vec![]
            }
        );
    }

    #[test]
    fn a_reordered_server_is_a_conflict_because_order_is_what_a_list_is() {
        let queued = edit("c", 1);
        assert_eq!(
            merge(
                Some(&v(&["a", "b"])),
                &v(&["b", "a"]),
                std::slice::from_ref(&queued)
            ),
            ShelfMergeOutcome::Conflict {
                discarded: vec![queued],
                settled: vec![]
            }
        );
    }

    #[test]
    fn an_edit_that_arrived_before_the_server_moved_is_settled_not_discarded() {
        let landed = edit("b", 1);
        let waiting = edit("d", 2);
        assert_eq!(
            merge(
                Some(&v(&["a"])),
                &v(&["a", "b", "c"]),
                &[landed.clone(), waiting.clone()]
            ),
            ShelfMergeOutcome::Conflict {
                discarded: vec![waiting],
                settled: vec![landed]
            }
        );
    }

    #[test]
    fn a_shelf_never_seen_from_this_device_is_pushed_to() {
        let queued = edit("b", 1);
        assert_eq!(
            merge(None, &v(&["a", "c"]), std::slice::from_ref(&queued)),
            ShelfMergeOutcome::Push(vec![queued])
        );
    }

    #[test]
    fn a_pending_entry_is_on_the_list_after_the_servers_own_and_marked() {
        let remote = vec![ShelfEntry {
            id: "a".into(),
            title: "A".into(),
            is_pending: false,
        }];
        let rows = projecting(&remote, &[edit("b", 2), edit("c", 1), edit("a", 0)]);
        let ids: Vec<&str> = rows.iter().map(|r| r.id.as_str()).collect();
        assert_eq!(ids, ["a", "c", "b"]);
        let pending: Vec<bool> = rows.iter().map(|r| r.is_pending).collect();
        assert_eq!(pending, [false, true, true]);
    }

    #[test]
    fn two_shelves_are_decided_apart_and_a_silent_one_keeps_its_edits() {
        let other = ShelfKey::new("server", 8, ShelfKind::ReadingList);
        let quiet = edit("b", 1);
        let clashing = ShelfEdit {
            shelf: other.clone(),
            ..edit("x", 2)
        };
        let away = ShelfEdit {
            shelf: ShelfKey::new("away", 1, ShelfKind::ReadingList),
            ..edit("y", 3)
        };
        let queue = ShelfEditQueue::default()
            .queueing(quiet.clone())
            .queueing(clashing.clone())
            .queueing(away)
            .recording(ShelfSnapshot {
                shelf: shelf(),
                entries: v(&["a"]),
            })
            .recording(ShelfSnapshot {
                shelf: other.clone(),
                entries: v(&["a"]),
            });
        let pull = ShelfPull::merging(
            &[
                ShelfSnapshot {
                    shelf: shelf(),
                    entries: v(&["a"]),
                },
                ShelfSnapshot {
                    shelf: other.clone(),
                    entries: v(&["z"]),
                },
            ],
            &queue,
        );
        assert_eq!(pull.to_push, vec![quiet]);
        assert_eq!(pull.to_drop, vec![clashing.clone()]);
        assert_eq!(pull.conflicts, vec![(other, vec![clashing])]);
    }

    #[test]
    fn the_queue_keeps_one_edit_per_entry_one_baseline_per_shelf_and_tells_once() {
        let queue = ShelfEditQueue::default()
            .queueing(edit("b", 1))
            .queueing(edit("b", 2))
            .recording(ShelfSnapshot {
                shelf: shelf(),
                entries: v(&["a"]),
            })
            .recording(ShelfSnapshot {
                shelf: shelf(),
                entries: v(&["a", "b"]),
            });
        assert_eq!(queue.edits.len(), 1);
        assert_eq!(queue.edits[0].made_at, Timestamp(2));
        assert_eq!(queue.baseline(&shelf()), Some(v(&["a", "b"]).as_slice()));
        let queue = queue.noting(ShelfConflictNotice::new(
            shelf(),
            "Crossover",
            vec!["Entry b".into()],
            Timestamp(5),
        ));
        let first = queue.next_notice().unwrap().clone();
        assert_eq!(first.discarded, ["Entry b"]);
        assert!(queue.acknowledging(&first.id).next_notice().is_none());
        assert_eq!(queue.removing_all_from("server"), ShelfEditQueue::default());
    }

    #[test]
    fn a_key_written_before_the_kind_existed_is_a_reading_list_and_kinds_do_not_collide() {
        let read: ShelfKey = serde_json::from_str(r#"{"sourceID":"server","shelfID":7}"#).unwrap();
        assert_eq!(read, ShelfKey::new("server", 7, ShelfKind::ReadingList));
        let collection = ShelfKey::new("server", 7, ShelfKind::Collection);
        assert_ne!(read.token(), collection.token());
        let queue: ShelfEditQueue = serde_json::from_str(r#"{"edits":[]}"#).unwrap();
        assert_eq!(queue, ShelfEditQueue::default());
        let text =
            serde_json::to_string(&ShelfEditQueue::default().queueing(edit("b", 1))).unwrap();
        let back: ShelfEditQueue = serde_json::from_str(&text).unwrap();
        assert_eq!(back.edits, vec![edit("b", 1)]);
    }
}
