//! The library as an app sees it, and the public Rust API the Linux app calls.
//!
//! - [`FolderSource`] opens a folder the reader chose and lists its publications.
//! - [`OpenPublication`] opens one for reading: its record, its page count, a page's bytes,
//!   size or RGBA pixels.
//! - [`ProgressStore`] reads and writes the reader's place.
//! - [`LibraryIndex`] turns the publications into the shelf on screen: search, filters,
//!   sorting under the reader's collation, Keep reading and Up next (task 2.8a).
//!
//! The Windows app reaches the same operations through `storyarc-ffi`. Everything here is
//! synchronous; call it off the interface thread.

pub mod facade;
pub mod query;

pub use facade::{FolderSource, LibraryError, OpenPublication, ProgressStore};

pub use query::{
    DownloadFilter, LibraryIndex, LibraryQuery, LibraryScope, LibrarySort, ProgressIndex,
    ProgressSummary, ReadState, YearRange,
};
