//! Where publications come from. Wave 2 holds the local folder: the walk, the listing a
//! returning app reconciles against, and the watcher over the native change notifiers.
//! Wave 3 adds the network sources: SMB, OPDS and Kavita (design.md, Decision 5, item 4).

pub mod index;
pub mod local;
pub mod smb;
pub mod snapshot;
pub mod watch;

pub use index::{IndexError, PublicationIndexer};
pub use local::{FolderScan, ScanReport, SkipReason, SkippedFile, WATCH_DIRECTORY_LIMIT};
pub use snapshot::{Change, Entry, FolderSnapshot};
