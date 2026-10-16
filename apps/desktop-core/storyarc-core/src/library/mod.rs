//! The library as an app sees it: queries over the publications a source holds (task 2.8a
//! of `desktop-clients`).

pub mod query;

pub use query::{
    DownloadFilter, LibraryIndex, LibraryQuery, LibraryScope, LibrarySort, ProgressIndex,
    ProgressSummary, ReadState, YearRange,
};
