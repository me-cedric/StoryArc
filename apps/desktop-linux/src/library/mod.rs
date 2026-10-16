//! The library's view-models: what the grid, the list and the search show, decided
//! without a widget in sight so the rules test on any host (tasks 2.35a and 2.35b).
//!
//! `entry.rs` is a local record shaped like the shared fixtures (`packages/test-fixtures`:
//! the comics manifest and the portability document's progress records). It stands in
//! for the core's library record until lane C's queries land, when the GTK side swaps
//! it for the core's type and these rules move behind them.

pub mod entry;
pub mod grid;
pub mod query;

pub use entry::{Cover, Format, LibraryEntry, Progress};
pub use grid::{CoverTier, GridModel, Selection, SeriesGroup};
pub use query::{Destination, Filters, QueryState, ReadState, Sort};

#[cfg(test)]
pub(crate) mod fixtures {
    //! Entries shaped like the shared corpus, so the view-model tests read as the
    //! fixtures do. Values come from `packages/test-fixtures/manifest.json` (comics)
    //! and `library/written-by-ios.json` (progress).

    use super::*;

    pub fn entry(id: &str, title: &str, pages: u32) -> LibraryEntry {
        LibraryEntry {
            id: format!("path:/{id}"),
            title: title.into(),
            series: None,
            issue: None,
            author: None,
            format: Format::Cbz,
            source: "Comics".into(),
            page_count: pages,
            progress: Progress::Unread,
            downloaded: false,
            added_at: 0,
            last_read_at: None,
            cover: Cover::Placeholder,
            cannot_open: None,
        }
    }

    pub fn corpus() -> Vec<LibraryEntry> {
        vec![
            LibraryEntry {
                series: Some("Fixture Series".into()),
                issue: Some(1),
                author: Some("Éric Fixture".into()),
                added_at: 10,
                progress: Progress::Reading { index: 12, of: 40 },
                last_read_at: Some(500),
                downloaded: true,
                cover: Cover::Full,
                ..entry("a.cbz", "Natural Sort", 12)
            },
            LibraryEntry {
                series: Some("Fixture Series".into()),
                issue: Some(2),
                added_at: 20,
                progress: Progress::Finished,
                last_read_at: Some(900),
                cover: Cover::Thumbnail,
                ..entry("b.cbz", "Nested Chapters", 6)
            },
            LibraryEntry {
                format: Format::Cbr,
                source: "NAS".into(),
                added_at: 30,
                ..entry("c.cbr", "Mislabelled Zip", 3)
            },
            LibraryEntry {
                format: Format::Epub,
                author: Some("Zoë Author".into()),
                added_at: 40,
                last_read_at: Some(100),
                progress: Progress::Reading { index: 3, of: 8 },
                ..entry("d.epub", "Ebook Fixture", 8)
            },
            LibraryEntry {
                format: Format::Cb7,
                added_at: 50,
                cannot_open: Some("library.cell.cannotOpen.cb7".into()),
                ..entry("e.cb7", "Seven Zip", 0)
            },
        ]
    }
}
