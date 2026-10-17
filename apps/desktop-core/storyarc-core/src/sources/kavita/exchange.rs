//! Kavita's pages and StoryArc's positions, by the shared rule (design.md, Decision 6:
//! "The app maps `position` and `totalProgression` to Kavita's fields the same way on every
//! platform"). Mirrored from StoryArcKit's `KavitaExchange` and asserted with its cases.
//!
//! Kavita counts pages *read*; a position names the page the reader is *on*, so the two
//! differ by one. A reflowable or listening position crosses by its fraction, the only part a
//! server counting pages can read, and comes back as a fraction with no locator.

use std::collections::HashMap;

use super::KavitaChapter;
use crate::domain::{ProgressPull, ReadingPosition, ReadingProgress};

/// One position a Kavita server has not been told about, and the record it becomes once told.
#[derive(Debug, Clone, PartialEq)]
pub struct KavitaOwed {
    pub chapter_id: i64,
    /// Kavita's `pageNum`: the page the reader is on, from zero.
    pub page_num: i64,
    /// A finished record is sent as a mark, not a page.
    pub is_mark_read: bool,
    /// What to write locally once the server has taken it, stamped as synchronised.
    pub settled: ReadingProgress,
}

/// A merge sorted into what to write now and what the server must be told.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct KavitaExchange {
    pub to_save: Vec<ReadingProgress>,
    pub owed: Vec<KavitaOwed>,
}

impl KavitaExchange {
    /// The position a chapter's `pagesRead` describes, clamped at both ends.
    pub fn position(pages_read: i64, pages: i64) -> ReadingPosition {
        if pages <= 0 {
            return ReadingPosition::page(0, 0);
        }
        ReadingPosition::page((pages_read - 1).clamp(0, pages - 1), pages)
    }

    /// The same, in the kind the local record already is.
    pub fn position_like(pages_read: i64, pages: i64, local: &ReadingPosition) -> ReadingPosition {
        let paged = Self::position(pages_read, pages);
        match local {
            ReadingPosition::Reflowable { .. } => ReadingPosition::reflowable(paged.fraction(), ""),
            _ => paged,
        }
    }

    /// The `pageNum` a server is told for a position in a chapter of `pages` pages.
    pub fn page_number(position: &ReadingPosition, pages: i64) -> i64 {
        if pages <= 1 {
            return 0;
        }
        match position {
            ReadingPosition::Page { index, .. } => (*index).clamp(0, pages - 1),
            ReadingPosition::Reflowable { .. } | ReadingPosition::Listening { .. } => {
                let page = (position.fraction() * (pages - 1) as f64).round() as i64;
                page.clamp(0, pages - 1)
            }
        }
    }

    /// The record a source has just taken, stamped with the position it took.
    pub fn settled(record: &ReadingProgress) -> ReadingProgress {
        ReadingProgress {
            synced_position: Some(record.position.clone()),
            ..record.clone()
        }
    }

    /// Sorts one pull against the chapters it came from, keyed by stable id. A record with no
    /// chapter, or a chapter with no pages, is owed nothing rather than guessed at.
    pub fn of(pull: &ProgressPull, chapters: &HashMap<String, KavitaChapter>) -> Self {
        let owed: Vec<KavitaOwed> = pull
            .to_push
            .iter()
            .filter_map(|record| {
                let chapter = chapters.get(&record.identity.stable_id())?;
                (chapter.pages > 0).then(|| KavitaOwed {
                    chapter_id: chapter.id,
                    page_num: Self::page_number(&record.position, chapter.pages),
                    is_mark_read: record.is_finished,
                    settled: Self::settled(record),
                })
            })
            .collect();
        let owing: Vec<String> = owed
            .iter()
            .map(|owed| owed.settled.identity.stable_id())
            .collect();
        let to_save = pull
            .to_save
            .iter()
            .map(|record| {
                if owing.contains(&record.identity.stable_id()) {
                    record.clone()
                } else {
                    Self::settled(record)
                }
            })
            .collect();
        Self { to_save, owed }
    }

    /// The position to seed a chapter with on its first open, or `None` when there is a local
    /// record already, nothing read on the server, or no pages to place it in.
    pub fn open_seed(
        pages_read: i64,
        pages: i64,
        existing: Option<&ReadingProgress>,
        reflowable: bool,
    ) -> Option<ReadingPosition> {
        if existing.is_some() || pages_read <= 0 || pages <= 0 {
            return None;
        }
        let paged = Self::position(pages_read, pages);
        Some(if reflowable {
            ReadingPosition::reflowable(paged.fraction(), "")
        } else {
            paged
        })
    }
}
