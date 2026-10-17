//! One pull from a source, sorted by ADR-0006's merge into what to write and what to send.
//! Mirrored from `ProgressPull.swift`; Kavita and the sync document both sort through it.

use super::identity::PublicationIdentity;
use super::progress::{ProgressMerge, ProgressMergeOutcome, ReadingPosition, ReadingProgress};

/// A conflict the reader is told about once, naming both positions.
#[derive(Debug, Clone, PartialEq)]
pub struct PullConflict {
    pub resolved: ReadingProgress,
    pub discarded: ReadingPosition,
}

/// What a pull asks of the local store and of the source.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ProgressPull {
    /// Records to write locally.
    pub to_save: Vec<ReadingProgress>,
    /// Records the source is behind on.
    pub to_push: Vec<ReadingProgress>,
    pub conflicts: Vec<PullConflict>,
}

impl ProgressPull {
    /// Merges each remote record with the local one `local` finds for its identity. A remote
    /// record with no local one is simply saved.
    pub fn merging(
        remote: &[ReadingProgress],
        local: impl Fn(&PublicationIdentity) -> Option<ReadingProgress>,
    ) -> Self {
        let mut pull = Self::default();
        for record in remote {
            let Some(held) = local(&record.identity) else {
                pull.to_save.push(record.clone());
                continue;
            };
            match ProgressMerge::merge(&held, record) {
                ProgressMergeOutcome::AdoptRemote(adopted) => pull.to_save.push(adopted),
                ProgressMergeOutcome::KeepLocalAndPush(kept) => pull.to_push.push(kept),
                ProgressMergeOutcome::Conflict {
                    resolved,
                    discarded,
                } => {
                    pull.to_save.push(resolved.clone());
                    // The local position won: the source must hear about it as well.
                    if resolved.position.matches(&held.position) {
                        pull.to_push.push(resolved.clone());
                    }
                    pull.conflicts.push(PullConflict {
                        resolved,
                        discarded,
                    });
                }
            }
        }
        pull
    }
}
