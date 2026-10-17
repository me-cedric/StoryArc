//! Where publications come from. Wave 2 holds the local folder: the walk, the listing a
//! returning app reconciles against, and the watcher over the native change notifiers.
//! SMB, OPDS and Kavita are wave 3 (design.md, Decision 5, item 4).

pub mod index;
pub mod local;
pub mod snapshot;
pub mod watch;

pub use index::{IndexError, PublicationIndexer};
pub use local::{FolderScan, ScanReport, SkipReason, SkippedFile, WATCH_DIRECTORY_LIMIT};
pub use snapshot::{Change, Entry, FolderSnapshot};
