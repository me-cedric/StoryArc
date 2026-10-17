//! Collections and reading lists (`collections-and-reading-lists`, task 3.7 of
//! `desktop-clients`), mirrored from StoryArcKit: the shelves as values ([`model`]), the
//! offline edit queue for server-backed shelves with its five-row merge ([`edits`]), and the
//! pins and remembered server shelves the home surface draws from ([`pins`]).

pub mod edits;
pub mod model;
pub mod pins;

pub use edits::{
    ShelfConflictNotice, ShelfEdit, ShelfEditQueue, ShelfEntry, ShelfKey, ShelfKind,
    ShelfMergeOutcome, ShelfPull, ShelfSnapshot,
};
pub use model::{
    EntryReading, ListProgress, PublicationCollection, ReadingList, ShelfOrigin, Shelves,
    cover_members, new_shelf_id, shelf_id,
};
pub use pins::{PinnedShelves, RememberedShelf, ShelfPin};
