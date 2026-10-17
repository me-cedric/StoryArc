//! Where someone stopped reading, and ADR-0006's rules for two devices that disagree.
//! Mirrored from `ReadingProgress.swift`.
//!
//! The wire shape is the one the library documents pin in `packages/test-fixtures/library`:
//! a position is tagged by `kind` (`page`, `reflowable`, `listening`) and a record carries
//! `identity`, `position`, `isFinished`, `finishedAt`, `updatedAt` and `syncedPosition`.

use serde::{Deserialize, Serialize};

use super::identity::PublicationIdentity;
use super::timestamp::Timestamp;

/// Where someone stopped reading.
///
/// A paged publication stores a page index. A reflowable one stores a fraction through the
/// content plus an opaque locator, because a reflowable page number is a function of the
/// reader's typography and is not stable across devices. A listening position is an
/// offset inside one part, with the part's length only when something knows it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ReadingPosition {
    Page {
        index: i64,
        of: i64,
    },
    #[serde(rename_all = "camelCase")]
    Reflowable {
        progression: f64,
        locator: String,
        /// Where the page starts as text, as the EPUB reader spells it. Opaque here.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        first_visible_element: Option<serde_json::Value>,
    },
    #[serde(rename_all = "camelCase")]
    Listening {
        part: i64,
        part_count: i64,
        offset_millis: i64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        of_millis: Option<i64>,
    },
}

impl ReadingPosition {
    pub fn page(index: i64, of: i64) -> Self {
        Self::Page { index, of }
    }

    pub fn reflowable(progression: f64, locator: impl Into<String>) -> Self {
        Self::Reflowable {
            progression,
            locator: locator.into(),
            first_visible_element: None,
        }
    }

    /// Normalised 0…1, so two positions can be compared regardless of kind.
    pub fn fraction(&self) -> f64 {
        match self {
            Self::Page { index, of } => {
                if *of <= 1 {
                    return if *of == 1 && *index >= 0 { 1.0 } else { 0.0 };
                }
                (*index as f64 / (*of - 1) as f64).clamp(0.0, 1.0)
            }
            Self::Reflowable { progression, .. } => progression.clamp(0.0, 1.0),
            Self::Listening {
                part,
                part_count,
                offset_millis,
                of_millis,
            } => {
                // The part, plus how far into it the listener is when anything knows. With
                // no duration the second term is zero rather than an estimate.
                if *part_count <= 0 {
                    return 0.0;
                }
                let within = of_millis
                    .filter(|total| *total > 0)
                    .map(|total| (*offset_millis as f64 / total as f64).clamp(0.0, 1.0))
                    .unwrap_or(0.0);
                ((*part as f64 + within) / *part_count as f64).clamp(0.0, 1.0)
            }
        }
    }

    /// Whether this describes the same point in a publication as another, by fraction
    /// rather than by kind: a store is entitled to keep a synced position as the one number
    /// that survives a change of typography.
    pub fn matches(&self, other: &Self) -> bool {
        self.fraction() == other.fraction()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadingProgress {
    pub identity: PublicationIdentity,
    pub position: ReadingPosition,
    pub is_finished: bool,
    /// When the finished flag first turned on. Moves once, where `updated_at` moves on
    /// every save; reopening a finished publication must not restate when it was finished.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finished_at: Option<Timestamp>,
    pub updated_at: Timestamp,
    /// The last position successfully exchanged with the source. Comparing against it is
    /// how the merge tells "changed since last sync" from "untouched".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub synced_position: Option<ReadingPosition>,
}

impl ReadingProgress {
    pub fn new(
        identity: PublicationIdentity,
        position: ReadingPosition,
        updated_at: Timestamp,
    ) -> Self {
        Self {
            identity,
            position,
            is_finished: false,
            finished_at: None,
            updated_at,
            synced_position: None,
        }
    }

    /// The record this one becomes when the finished flag is set or cleared: the
    /// timestamp is stamped when the flag turns on, kept while it stays on, and dropped
    /// when it turns off.
    pub fn finished(&self, finished: bool, at: Timestamp) -> Self {
        Self {
            is_finished: finished,
            finished_at: if finished {
                self.finished_at.or(Some(at))
            } else {
                None
            },
            updated_at: at,
            ..self.clone()
        }
    }
}

/// The outcome of merging a local record with a remote one.
#[derive(Debug, Clone, PartialEq)]
pub enum ProgressMergeOutcome {
    /// Remote adopted with no user-visible notice.
    AdoptRemote(ReadingProgress),
    /// Local kept; push it to the server.
    KeepLocalAndPush(ReadingProgress),
    /// Both moved since the last sync. The further position wins, and the user is told
    /// once — naming both — with the option to take the other.
    Conflict {
        resolved: ReadingProgress,
        discarded: ReadingPosition,
    },
}

/// ADR-0006's conflict rules, in one place, so every platform can be checked against the
/// same table.
///
/// | Situation | Result |
/// | --- | --- |
/// | Remote ahead, local untouched since last sync | adopt remote silently |
/// | Remote behind local | keep local, push |
/// | Both changed since last sync | further wins, tell the user once |
/// | One finished, one partial | finished wins |
/// | No watermark at all | further wins, quietly |
pub struct ProgressMerge;

impl ProgressMerge {
    pub fn merge(local: &ReadingProgress, remote: &ReadingProgress) -> ProgressMergeOutcome {
        // Finished is sticky. Unmarking a finished publication is a deliberate act; losing
        // it to a stale sync is never what someone wanted.
        if remote.is_finished && !local.is_finished {
            return ProgressMergeOutcome::AdoptRemote(remote.clone());
        }
        if local.is_finished && !remote.is_finished {
            return ProgressMergeOutcome::KeepLocalAndPush(local.clone());
        }

        let remote_ahead = remote.position.fraction() > local.position.fraction();
        let quietly = || {
            if remote_ahead {
                ProgressMergeOutcome::AdoptRemote(remote.clone())
            } else {
                ProgressMergeOutcome::KeepLocalAndPush(local.clone())
            }
        };

        // An absent watermark means this device has never exchanged a position with any
        // source. That is not evidence that the local side moved.
        let Some(watermark) = &local.synced_position else {
            return quietly();
        };
        if watermark.matches(&local.position) {
            // Nothing to lose locally: take whichever is further, quietly.
            return quietly();
        }
        // Local moved since the last sync. Did remote move too?
        if watermark.matches(&remote.position) {
            return ProgressMergeOutcome::KeepLocalAndPush(local.clone());
        }
        // Genuine conflict. Furthest wins — clock skew between a phone and a NAS is real,
        // and being a few pages ahead is recoverable in a way that losing an evening's
        // reading is not.
        if remote_ahead {
            return ProgressMergeOutcome::Conflict {
                resolved: remote.clone(),
                discarded: local.position.clone(),
            };
        }
        if local.position.fraction() > remote.position.fraction() {
            return ProgressMergeOutcome::Conflict {
                resolved: local.clone(),
                discarded: remote.position.clone(),
            };
        }
        // Identical positions are not a conflict at all.
        ProgressMergeOutcome::KeepLocalAndPush(local.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_paged_fraction_runs_from_zero_to_one_and_a_single_page_is_whole() {
        assert_eq!(ReadingPosition::page(0, 100).fraction(), 0.0);
        assert_eq!(ReadingPosition::page(99, 100).fraction(), 1.0);
        assert_eq!(ReadingPosition::page(0, 1).fraction(), 1.0);
        assert_eq!(ReadingPosition::page(0, 0).fraction(), 0.0);
    }

    #[test]
    fn a_reflowable_progression_is_clamped() {
        assert_eq!(ReadingPosition::reflowable(-0.5, "x").fraction(), 0.0);
        assert_eq!(ReadingPosition::reflowable(1.5, "x").fraction(), 1.0);
    }

    #[test]
    fn a_listening_fraction_refines_by_the_part_only_when_a_duration_is_known() {
        let without = ReadingPosition::Listening {
            part: 2,
            part_count: 9,
            offset_millis: 61_500,
            of_millis: None,
        };
        let with = ReadingPosition::Listening {
            part: 2,
            part_count: 9,
            offset_millis: 300_000,
            of_millis: Some(600_000),
        };
        assert!((without.fraction() - 2.0 / 9.0).abs() < 1e-12);
        assert!((with.fraction() - 2.5 / 9.0).abs() < 1e-12);
    }

    #[test]
    fn the_wire_shape_matches_the_library_documents() {
        let json = r#"{"index":12,"kind":"page","of":40}"#;
        let position: ReadingPosition = serde_json::from_str(json).unwrap();
        assert_eq!(position, ReadingPosition::page(12, 40));
        assert_eq!(
            serde_json::to_string(&position).unwrap(),
            r#"{"kind":"page","index":12,"of":40}"#
        );
        let listening: ReadingPosition = serde_json::from_str(
            r#"{"kind":"listening","ofMillis":600000,"offsetMillis":61500,"part":2,"partCount":9}"#,
        )
        .unwrap();
        assert!(matches!(
            listening,
            ReadingPosition::Listening { part: 2, .. }
        ));
    }

    #[test]
    fn finishing_stamps_once_and_unfinishing_drops_the_stamp() {
        let record = ReadingProgress::new(
            PublicationIdentity::digest("d"),
            ReadingPosition::page(3, 10),
            Timestamp(100),
        );
        let done = record.finished(true, Timestamp(200));
        assert_eq!(done.finished_at, Some(Timestamp(200)));
        let still = done.finished(true, Timestamp(300));
        assert_eq!(still.finished_at, Some(Timestamp(200)));
        assert_eq!(still.updated_at, Timestamp(300));
        assert_eq!(still.finished(false, Timestamp(400)).finished_at, None);
    }
}
