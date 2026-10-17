//! Library portability and sync (`library-portability`, `library-sync`; task 3.8 of
//! `desktop-clients`), mirrored from StoryArcKit so a document written on a phone opens here
//! and one written here opens on a phone.
//!
//! [`document`] is the shape, [`coder`] reads and writes it with the version rules and strips
//! secrets from addresses, [`sealing`] seals and opens the secrets a reader chose to carry,
//! [`merge`] merges a document into what this device holds, and [`sync`] keeps one document
//! in a place the reader configured.

pub mod coder;
pub mod document;
pub mod merge;
pub mod sealing;
pub mod sync;

pub use coder::{DocumentFailure, decode, encode, exportable_address};
pub use document::{LibraryBody, LibraryDocument, LibrarySecrets};
pub use merge::{LibrarySnapshot, Merged, merging};
pub use sync::{FolderPlace, LibrarySync, SyncOutcome, SyncPlace};
